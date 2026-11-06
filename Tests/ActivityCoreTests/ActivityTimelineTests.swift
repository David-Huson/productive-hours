import Foundation
import Testing
@testable import ActivityCore

@Test func timelineClipsAtMidnightPreservesTotalsAndDoesNotFillGaps() {
    var calendar = Calendar(identifier: .gregorian); calendar.timeZone = .gmt
    let rows = [
        Interval(start: 86_390_000, end: 86_410_000, source: Source(productivity: .productive), activity: .active),
        Interval(start: 86_420_000, end: 86_430_000, source: Source(), activity: .unknown, reason: "paused")
    ]
    let days = ActivityTimeline.days(intervals: rows.reversed(), from: Date(epochMS: 0), through: Date(epochMS: 86_400_000), calendar: calendar)
    #expect(days.count == 2)
    #expect(days[0].productive == 10)
    #expect(days[1].productive == 10)
    #expect(days[1].totals[.untracked] == 10)
    #expect(days[1].interval(at: 86_415_000) == nil)
    #expect(days[1].interval(at: 86_410_000) == nil)
    #expect(days[1].interval(at: 86_420_000)?.reason == "paused")
}

@Test func timelineUsesCalendarDSTBoundsAndLimitsRange() {
    var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "America/Chicago")!
    for (month, day, hours) in [(3, 8, 23), (11, 1, 25)] {
        let date = calendar.date(from: DateComponents(year: 2026, month: month, day: day))!
        let rows = ActivityTimeline.days(intervals: [], from: date, through: date, calendar: calendar)
        #expect(rows[0].end.timeIntervalSince(rows[0].start) == Double(hours * 3600))
    }
    #expect(ActivityTimeline.days(intervals: [], from: Date(epochMS: 0), through: Date(epochMS: 100 * 86_400_000), calendar: calendar).count == 31)
}

@Test func timelineClassificationAndMergeKeepDistinctReasons() {
    var calendar = Calendar(identifier: .gregorian); calendar.timeZone = .gmt
    let source = Source(productivity: .productive)
    let rows = [Interval(start: 0, end: 1000, source: source, activity: .passive),
                Interval(start: 1000, end: 2000, source: source, activity: .passive),
                Interval(start: 2000, end: 3000, source: source, activity: .passive, reason: "call_audio")]
    let day = ActivityTimeline.days(intervals: rows, from: Date(epochMS: 0), through: Date(epochMS: 0), calendar: calendar)[0]
    #expect(day.intervals.count == 2)
    #expect(day.productive == 3)
    #expect(TimelineCategory.category(Interval(start: 0, end: 1000, source: source, activity: .inactive)) == .inactive)
    #expect(TimelineCategory.category(Interval(start: 0, end: 1000, source: Source(productivity: .productive, privateBrowsing: true), activity: .active)) == .ignored)
}

@Test func timelineViewportKeepsAnchorAndClampsEdges() {
    var view = TimelineViewport()
    view.zoom(by: 2, anchor: 0.25)
    #expect(view.span == 0.5)
    #expect(view.start == 0.125)
    view.pan(by: 10); #expect(view.start == 0.5)
    view.pan(by: -10); #expect(view.start == 0)
    view.zoom(by: 100000); #expect(view.span == 1.0 / 1440)
    view.zoom(by: 0.000001); #expect(view.span == 1)
    #expect(view.start == 0)
}
