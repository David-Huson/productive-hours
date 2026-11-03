import Foundation

public struct TrackingGapSummary: Sendable {
    public var paused: Double = 0
    public var collection: Double = 0
    public var other: Double = 0
    public var total: Double { paused + collection + other }

    public init(intervals: [Interval], start: Date, end: Date) {
        for interval in intervals where interval.activity == .unknown {
            let seconds = Double(max(0, min(interval.end, end.epochMS) - max(interval.start, start.epochMS))) / 1000
            switch interval.reason {
            case "paused": paused += seconds
            case "collector_gap": collection += seconds
            default: other += seconds
            }
        }
    }
}
