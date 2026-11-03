import Foundation
import Testing
@testable import ActivityCore

@Test func gapsSeparatePausesFromCollectionAndExcludeUndefinedActivity() {
    let rows = [
        Interval(start: 0, end: 100_000, source: Source(), activity: .unknown, reason: "paused"),
        Interval(start: 100_000, end: 120_000, source: Source(), activity: .unknown, reason: "collector_gap"),
        Interval(start: 120_000, end: 150_000, source: Source(productivity: .undefined), activity: .active),
        Interval(start: 150_000, end: 160_000, source: Source(), activity: .unknown, reason: "other")
    ]
    let summary = TrackingGapSummary(intervals: rows, start: Date(epochMS: 50_000), end: Date(epochMS: 155_000))
    #expect(summary.paused == 50)
    #expect(summary.collection == 20)
    #expect(summary.other == 5)
    #expect(summary.total == 75)
}
