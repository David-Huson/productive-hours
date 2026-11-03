import Foundation
import CSQLite
import ActivityCore

public enum StoreError: Error, LocalizedError {
    case database(Int32), invalidData
    public var errorDescription: String? {
        switch self {
        case .database(let code): return "Local storage failed (SQLite code \(code)). Tracking is stopped; existing data is preserved."
        case .invalidData: return "Stored data could not be decoded. Existing data is preserved."
        }
    }
}

private enum SQLValue { case text(String), integer(Int64) }

/// Single owner only: TrackingService serializes every access on the main actor.
public final class Store {
    private var db: OpaquePointer?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    public let url: URL
    public init(url: URL) throws {
        self.url = url
        let fm = FileManager.default
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.deletingLastPathComponent().path)
        let status = sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil)
        guard status == SQLITE_OK else { if let db { sqlite3_close(db) }; db = nil; throw StoreError.database(status) }
        do {
            sqlite3_busy_timeout(db, 2000)
            try execute("PRAGMA journal_mode=WAL")
            try execute("PRAGMA synchronous=FULL")
            try execute("PRAGMA foreign_keys=ON")
            try execute("PRAGMA secure_delete=ON")
            let version = try scalar("PRAGMA user_version")
            guard version <= 1 else { throw StoreError.invalidData }
            try transaction {
                try execute("CREATE TABLE IF NOT EXISTS intervals(id TEXT PRIMARY KEY, start INTEGER NOT NULL, end INTEGER NOT NULL CHECK(end > start), payload TEXT NOT NULL)")
                try execute("CREATE INDEX IF NOT EXISTS interval_time ON intervals(start,end)")
                try execute("CREATE TRIGGER IF NOT EXISTS no_interval_overlap BEFORE INSERT ON intervals WHEN EXISTS(SELECT 1 FROM intervals WHERE start < NEW.end AND end > NEW.start) BEGIN SELECT RAISE(ABORT,'overlap'); END")
                try execute("CREATE TABLE IF NOT EXISTS values_store(key TEXT PRIMARY KEY, payload TEXT NOT NULL)")
                try execute("CREATE TABLE IF NOT EXISTS rule_revisions(id TEXT PRIMARY KEY, payload TEXT NOT NULL)")
                try execute("CREATE TABLE IF NOT EXISTS audit(id TEXT PRIMARY KEY, time INTEGER NOT NULL, payload TEXT NOT NULL)")
                try execute("CREATE TABLE IF NOT EXISTS reference_totals(id TEXT PRIMARY KEY, payload TEXT NOT NULL)")
                try execute("CREATE TABLE IF NOT EXISTS manual_work(id TEXT PRIMARY KEY, payload TEXT NOT NULL)")
                try execute("CREATE TABLE IF NOT EXISTS archives(id TEXT PRIMARY KEY, payload TEXT NOT NULL)")
                try execute("PRAGMA user_version=1")
            }
            try protectFiles()
        } catch { sqlite3_close(db); db = nil; throw error }
    }
    deinit { sqlite3_close(db) }

    private func protectFiles() throws {
        for path in [url.path, url.path + "-wal", url.path + "-shm"] where FileManager.default.fileExists(atPath: path) {
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
        }
    }
    private func prepare(_ sql: String, _ values: [SQLValue]) throws -> OpaquePointer {
        var statement: OpaquePointer?
        let code = sqlite3_prepare_v2(db, sql, -1, &statement, nil)
        guard code == SQLITE_OK, let statement else { throw StoreError.database(code) }
        for (offset, value) in values.enumerated() {
            let index = Int32(offset + 1)
            let status: Int32
            switch value {
            case .integer(let value): status = sqlite3_bind_int64(statement, index, value)
            case .text(let value): status = sqlite3_bind_text(statement, index, value, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            }
            guard status == SQLITE_OK else { sqlite3_finalize(statement); throw StoreError.database(status) }
        }
        return statement
    }
    private func execute(_ sql: String, _ values: [SQLValue] = []) throws {
        let statement = try prepare(sql, values); defer { sqlite3_finalize(statement) }
        var result = sqlite3_step(statement)
        while result == SQLITE_ROW { result = sqlite3_step(statement) }
        guard result == SQLITE_DONE else { throw StoreError.database(result) }
    }
    private func scalar(_ sql: String) throws -> Int64 {
        let statement = try prepare(sql, []); defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { throw StoreError.invalidData }
        return sqlite3_column_int64(statement, 0)
    }
    private func transaction(_ body: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE")
        do { try body(); try execute("COMMIT") } catch { try? execute("ROLLBACK"); throw error }
    }
    private func json<T: Encodable>(_ value: T) throws -> String { String(decoding: try encoder.encode(value), as: UTF8.self) }
    private func read<T: Decodable>(_ sql: String, _ values: [SQLValue] = []) throws -> [T] {
        let statement = try prepare(sql, values); defer { sqlite3_finalize(statement) }
        var rows: [T] = []
        while true {
            let code = sqlite3_step(statement)
            if code == SQLITE_DONE { return rows }
            guard code == SQLITE_ROW, let text = sqlite3_column_text(statement, 0) else { throw StoreError.database(code) }
            do { rows.append(try decoder.decode(T.self, from: Data(String(cString: text).utf8))) }
            catch { throw StoreError.invalidData }
        }
    }
    public func load<T: Decodable>(_ key: String, as type: T.Type) throws -> T? {
        let rows: [T] = try read("SELECT payload FROM values_store WHERE key=?", [.text(key)])
        return rows.first
    }
    public func save<T: Encodable>(_ key: String, value: T) throws {
        try execute("INSERT INTO values_store(key,payload) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET payload=excluded.payload", [.text(key), .text(try json(value))])
    }
    public func remove(_ key: String) throws { try execute("DELETE FROM values_store WHERE key=?", [.text(key)]) }
    public func intervals() throws -> [Interval] { try read("SELECT payload FROM intervals ORDER BY start") }
    public func commit(_ intervals: [Interval], checkpoint: TrackingEngine) throws {
        try transaction {
            if let durable = try load("checkpoint", as: TrackingEngine.self), checkpoint.boundary < durable.boundary { throw StoreError.invalidData }
            for row in intervals {
                let existing: [Interval] = try read("SELECT payload FROM intervals WHERE id=?", [.text(row.id)])
                if let previous = existing.first {
                    guard previous == row else { throw StoreError.invalidData }
                    continue
                }
                try execute("INSERT INTO intervals VALUES(?,?,?,?)", [.text(row.id), .integer(row.start), .integer(row.end), .text(try json(row))])
            }
            try save("checkpoint", value: checkpoint)
        }
    }
    public func saveRuleSet(_ rules: [ClassificationRule], action: String = "forward_only") throws {
        let revision = RuleRevision(id: UUID().uuidString, date: Date(), action: action, rules: rules)
        try transaction {
            try execute("INSERT INTO rule_revisions VALUES(?,?)", [.text(revision.id), .text(try json(revision))])
            try save("rules", value: rules)
        }
    }
    public func ruleRevisions() throws -> [RuleRevision] { try read("SELECT payload FROM rule_revisions ORDER BY rowid DESC") }
    /// Re-resolve retained intervals with the current rule set. Skips private browsing and call-audio rows.
    public func reconcileIntervalSources(rules: [ClassificationRule]) throws -> Int {
        let rows = try intervals()
        var updates: [Interval] = []
        for row in rows {
            if row.source.privateBrowsing || row.reason == "call_audio" { continue }
            let resolved = RuleEvaluator.resolve(app: row.source.app, host: row.source.host, rules: rules)
            guard resolved != row.source else { continue }
            var updated = row
            updated.source = resolved
            updates.append(updated)
        }
        guard !updates.isEmpty else { return 0 }
        try transaction {
            for row in updates {
                try execute("UPDATE intervals SET payload=? WHERE id=?", [.text(try json(row)), .text(row.id)])
            }
        }
        return updates.count
    }
    public func reclassify(rules: [ClassificationRule], previousRules: [ClassificationRule], at time: Date) throws {
        let before = try intervals()
        let after = before.map { row in
            var result = row
            if row.source.privateBrowsing || row.reason == "call_audio" { return row }
            result.source = RuleEvaluator.resolve(app: row.source.app, host: row.source.host, rules: rules)
            return result
        }
        try transaction {
            let audit = RuleAudit(id: UUID().uuidString, date: time, before: before, previousRules: previousRules)
            try execute("INSERT INTO audit VALUES(?,?,?)", [.text(audit.id), .integer(time.epochMS), .text(try json(audit))])
            for row in after { try execute("UPDATE intervals SET payload=? WHERE id=?", [.text(try json(row)), .text(row.id)]) }
            try save("rules", value: rules)
            let revision = RuleRevision(id: UUID().uuidString, date: time, action: "historical_recalculation", rules: rules)
            try execute("INSERT INTO rule_revisions VALUES(?,?)", [.text(revision.id), .text(try json(revision))])
        }
    }
    public func undoReclassification() throws -> [ClassificationRule]? {
        let audits: [RuleAudit] = try read("SELECT payload FROM audit ORDER BY time DESC LIMIT 1")
        guard let audit = audits.first else { return nil }
        try transaction {
            for row in audit.before { try execute("UPDATE intervals SET payload=? WHERE id=?", [.text(try json(row)), .text(row.id)]) }
            try save("rules", value: audit.previousRules)
            try execute("DELETE FROM audit WHERE id=?", [.text(audit.id)])
            let revision = RuleRevision(id: UUID().uuidString, date: Date(), action: "undo_recalculation", rules: audit.previousRules)
            try execute("INSERT INTO rule_revisions VALUES(?,?)", [.text(revision.id), .text(try json(revision))])
        }
        return audit.previousRules
    }
    public func addReference(_ value: ReferenceTotal) throws { try execute("INSERT INTO reference_totals VALUES(?,?)", [.text(value.id), .text(try json(value))]) }
    public func references() throws -> [ReferenceTotal] { try read("SELECT payload FROM reference_totals") }
    public func importReferences(_ values: [ReferenceTotal]) throws { try transaction { for value in values { try addReference(value) } } }
    public func addManual(_ value: ManualWork) throws { try execute("INSERT INTO manual_work VALUES(?,?)", [.text(value.id), .text(try json(value))]) }
    public func manualWork() throws -> [ManualWork] { try read("SELECT payload FROM manual_work") }
    public func archives() throws -> [ArchivedDay] { try read("SELECT payload FROM archives") }
    public func retain(settings: AppSettings, now: Date) throws {
        let cutoff = settings.calendar.startOfDay(for: settings.calendar.date(byAdding: .day, value: -settings.retentionDays, to: now)!)
        let expired: [Interval] = try read("SELECT payload FROM intervals WHERE end <= ?", [.integer(cutoff.epochMS)])
        let days = Metrics.aggregate(expired, settings: settings)
        try transaction {
            for day in days {
                let archive = ArchivedDay(id: UUID().uuidString, timezone: settings.timezone, total: day, configuration: settings)
                try execute("INSERT INTO archives VALUES(?,?)", [.text(archive.id), .text(try json(archive))])
            }
            try execute("DELETE FROM intervals WHERE end <= ?", [.integer(cutoff.epochMS)])
            // Audits include raw rows and obey the same detailed-data retention boundary.
            try execute("DELETE FROM audit")
            let old = now.addingTimeInterval(-365 * 86400)
            for archive in try archives() where archive.total.date < old {
                try execute("DELETE FROM archives WHERE id=?", [.text(archive.id)])
            }
        }
    }
    public func deleteAll() throws {
        try transaction {
            for table in ["intervals", "values_store", "audit", "reference_totals", "manual_work", "archives", "rule_revisions"] { try execute("DELETE FROM \(table)") }
        }
        try execute("VACUUM")
        try execute("PRAGMA wal_checkpoint(TRUNCATE)")
    }
}

private struct RuleAudit: Codable { var id: String; var date: Date; var before: [Interval]; var previousRules: [ClassificationRule] }
public struct ArchivedDay: Codable, Sendable { public var id: String; public var timezone: String; public var total: DayTotal; public var configuration: AppSettings }

public struct RuleRevision: Codable, Identifiable, Sendable { public var id: String; public var date: Date; public var action: String; public var rules: [ClassificationRule] }
