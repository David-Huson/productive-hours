import Foundation

public struct ReferenceTotal: Codable, Identifiable, Sendable {
    public var id = UUID().uuidString
    public var day: String
    public var timezone: String
    public var metric: String
    public var seconds: Double
    public var importedAt = Date()
    public var source: String
    public var correctsID: String?
    public init(day: String, timezone: String, metric: String, seconds: Double, source: String, correctsID: String? = nil) {
        self.day = day; self.timezone = timezone; self.metric = metric; self.seconds = seconds; self.source = source; self.correctsID = correctsID
    }
}
public struct ManualWork: Codable, Identifiable, Sendable {
    public var id = UUID().uuidString
    public var start: Date
    public var end: Date
    public var kind: String
    public var seconds: Double { max(0, end.timeIntervalSince(start)) }
    public init(start: Date, end: Date, kind: String = "user_declared_meeting") { self.start = start; self.end = end; self.kind = kind }
}
public enum CSVError: Error, LocalizedError {
    case invalid(String)
    public var errorDescription: String? { if case .invalid(let message) = self { return message }; return nil }
}
public enum CalibrationCSV {
    /// Accepted interchange schema is deliberately explicit. Other vendor schemas need mapping first.
    public static func parse(_ text: String, timezone: String, metric: String) throws -> [ReferenceTotal] {
        guard TimeZone(identifier: timezone) != nil, !metric.trimmingCharacters(in: .whitespaces).isEmpty else { throw CSVError.invalid("Choose a valid reference timezone and metric.") }
        guard text.utf8.count <= 2_000_000 else { throw CSVError.invalid("CSV exceeds 2 MB.") }
        var rows: [[String]] = [], row: [String] = [], field = "", quoted = false
        var iterator = text.replacingOccurrences(of: "\r\n", with: "\n").makeIterator()
        var next = iterator.next()
        while let ch = next {
            next = iterator.next()
            if ch == "\"" {
                if quoted && next == "\"" { field.append("\""); next = iterator.next() }
                else { quoted.toggle() }
            } else if ch == "," && !quoted { row.append(field); field = "" }
            else if ch == "\n" && !quoted { row.append(field); if row.contains(where: { !$0.isEmpty }) { rows.append(row) }; row = []; field = "" }
            else { field.append(ch) }
        }
        guard !quoted else { throw CSVError.invalid("CSV contains an unclosed quoted field.") }
        row.append(field); if row.contains(where: { !$0.isEmpty }) { rows.append(row) }
        guard let header = rows.first,
              let dateIndex = header.firstIndex(of: "date"), let secondsIndex = header.firstIndex(of: "productive_seconds") else {
            throw CSVError.invalid("Expected CSV columns date and productive_seconds. Dates must use YYYY-MM-DD; totals must be seconds.")
        }
        var seen: Set<String> = []
        return try rows.dropFirst().enumerated().map { offset, fields in
            guard fields.count == header.count else { throw CSVError.invalid("Row \(offset + 2) has the wrong number of columns.") }
            let day = fields[dateIndex]
            let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"; formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(identifier: timezone); formatter.isLenient = false
            guard let date = formatter.date(from: day), formatter.string(from: date) == day,
                  let seconds = Double(fields[secondsIndex]), seconds.isFinite, seconds >= 0, seconds <= 90000, seen.insert(day).inserted else {
                throw CSVError.invalid("Row \(offset + 2): invalid or duplicate date, or invalid productive seconds.")
            }
            return ReferenceTotal(day: day, timezone: timezone, metric: metric, seconds: seconds, source: "csv")
        }
    }
}

public struct ComparisonSummary: Sendable {
    public var count: Int
    public var estimated: Double
    public var reference: Double
    public var medianAbsoluteDailyError: Double
    public var delta: Double { estimated - reference }
    public var percentage: Double? { reference == 0 ? nil : delta / reference * 100 }
    public static func calculate(references: [ReferenceTotal], days: [DayTotal], metric: String, timezone: String) -> ComparisonSummary {
        let superseded = Set(references.compactMap(\.correctsID))
        let relevant = references.filter { !superseded.contains($0.id) && $0.metric == metric && $0.timezone == timezone }
        var estimated = 0.0, reference = 0.0, errors: [Double] = []
        for value in relevant {
            guard let day = days.first(where: { $0.id == value.day }) else { continue }
            let local = metric == "Productive Active" ? day.active : day.productive
            estimated += local; reference += value.seconds; errors.append(abs(local - value.seconds))
        }
        errors.sort()
        let median: Double
        if errors.isEmpty { median = 0 }
        else if errors.count % 2 == 0 { median = (errors[errors.count / 2 - 1] + errors[errors.count / 2]) / 2 }
        else { median = errors[errors.count / 2] }
        return ComparisonSummary(count: errors.count, estimated: estimated, reference: reference, medianAbsoluteDailyError: median)
    }
}
