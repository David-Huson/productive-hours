import Foundation

public enum TimelineCategory: String, CaseIterable, Sendable {
    case productiveActive = "Productive active", productivePassive = "Productive passive"
    case unproductiveActive = "Unproductive active", unproductivePassive = "Unproductive passive"
    case undefinedActive = "Undefined active", undefinedPassive = "Undefined passive"
    case ignored = "Ignored", inactive = "Inactive", untracked = "Untracked"

    public static func category(_ row: Interval) -> Self {
        if row.activity == .unknown { return .untracked }
        if row.activity == .inactive { return .inactive }
        if row.source.privateBrowsing || row.source.productivity == .ignored { return .ignored }
        switch (row.source.productivity, row.activity) {
        case (.productive, .active): return .productiveActive
        case (.productive, _): return .productivePassive
        case (.unproductive, .active): return .unproductiveActive
        case (.unproductive, _): return .unproductivePassive
        case (.undefined, .active): return .undefinedActive
        default: return .undefinedPassive
        }
    }
}

public struct TimelineDay: Identifiable, Sendable {
    public var id: Date { start }
    public let start: Date
    public let end: Date
    public var intervals: [Interval] = []
    public var totals: [TimelineCategory: Double] = [:]
    public var productive: Double { totals[.productiveActive, default: 0] + totals[.productivePassive, default: 0] }

    /// First interval ending after the query, also used to cull rendering outside the viewport.
    public func index(at time: Int64) -> Int {
        var low = 0, high = intervals.count
        while low < high {
            let mid = (low + high) / 2
            if intervals[mid].end <= time { low = mid + 1 } else { high = mid }
        }
        return low
    }
    public func interval(at time: Int64) -> Interval? {
        let i = index(at: time)
        guard i < intervals.count, intervals[i].start <= time else { return nil }
        return intervals[i]
    }
}

public enum ActivityTimeline {
    /// At most 31 reporting-calendar days. No synthetic intervals fill missing observations.
    public static func days(intervals: [Interval], from: Date, through: Date, calendar: Calendar) -> [TimelineDay] {
        let first = calendar.startOfDay(for: from)
        let last = calendar.startOfDay(for: through)
        guard first <= last else { return [] }
        var days: [TimelineDay] = []
        var date = first
        while date <= last && days.count < 31 {
            guard let end = calendar.date(byAdding: .day, value: 1, to: date) else { break }
            days.append(TimelineDay(start: date, end: end))
            date = end
        }
        guard let end = days.last?.end else { return [] }
        let rows = intervals.filter { $0.end > first.epochMS && $0.start < end.epochMS }.sorted { $0.start < $1.start }
        var dayIndex = 0
        for row in rows {
            while dayIndex < days.count && days[dayIndex].end.epochMS <= row.start { dayIndex += 1 }
            var index = dayIndex
            while index < days.count && days[index].start.epochMS < row.end {
                var clipped = row
                clipped.start = max(row.start, days[index].start.epochMS)
                clipped.end = min(row.end, days[index].end.epochMS)
                if clipped.end > clipped.start {
                    let category = TimelineCategory.category(clipped)
                    days[index].totals[category, default: 0] += clipped.seconds
                    if let previous = days[index].intervals.last,
                       previous.end == clipped.start, previous.source == clipped.source,
                       previous.activity == clipped.activity, previous.reason == clipped.reason {
                        days[index].intervals[days[index].intervals.count - 1].end = clipped.end
                    } else { days[index].intervals.append(clipped) }
                }
                index += 1
            }
        }
        return days
    }
}

public struct TimelineViewport: Equatable, Sendable {
    public private(set) var start: Double = 0
    public private(set) var span: Double = 1
    public init() {}
    public mutating func zoom(by scale: Double, anchor: Double = 0.5) {
        guard scale.isFinite, scale > 0 else { return }
        let fraction = min(1, max(0, anchor))
        let focus = start + span * fraction
        span = min(1, max(1.0 / 1440, span / scale))
        start = min(1 - span, max(0, focus - span * fraction))
    }
    public mutating func pan(by fraction: Double) {
        guard fraction.isFinite else { return }
        start = min(1 - span, max(0, start + fraction))
    }
}
