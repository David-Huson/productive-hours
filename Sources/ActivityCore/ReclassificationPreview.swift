import Foundation

public struct ReclassificationPreview: Sendable {
    public struct Change: Identifiable, Sendable {
        public var id: String
        public var source: Source
        public var before: Double
        public var after: Double
        public var delta: Double { after - before }
    }
    public let rules: [ClassificationRule]
    public let before: Double
    public let after: Double
    public let changes: [Change]

    public init(intervals: [Interval], rules: [ClassificationRule]) {
        self.rules = rules
        var before = 0.0, after = 0.0
        var grouped: [String: Change] = [:]
        for row in intervals {
            let updated = Self.reclassified(row, rules: rules)
            let old = row.productive ? row.seconds : 0
            let new = updated.productive ? updated.seconds : 0
            before += old; after += new
            guard old != new else { continue }
            let id = row.source.app + "\n" + (row.source.host ?? "")
            var change = grouped[id] ?? Change(id: id, source: row.source, before: 0, after: 0)
            change.before += old; change.after += new
            grouped[id] = change
        }
        self.before = before; self.after = after
        changes = grouped.values.filter { abs($0.delta) > 0.001 }.sorted {
            abs($0.delta) == abs($1.delta) ? $0.id < $1.id : abs($0.delta) > abs($1.delta)
        }
    }

    public func matches(rules: [ClassificationRule]) -> Bool { self.rules == rules }

    public static func reclassified(_ row: Interval, rules: [ClassificationRule]) -> Interval {
        guard !row.source.privateBrowsing, row.reason != "call_audio" else { return row }
        var updated = row
        updated.source = RuleEvaluator.resolve(app: row.source.app, host: row.source.host, rules: rules)
        return updated
    }
}
