import Foundation
import Testing
@testable import ActivityCore

private func sampleWeek(calendar: Calendar) -> WeeklyMetrics {
    let start = calendar.date(from: DateComponents(year: 2026, month: 11, day: 3))!
    let day = DayTotal(id: "2026-11-03", date: start, active: 3600, passive: 1800)
    return WeeklyMetrics(
        start: start,
        end: calendar.date(byAdding: .day, value: 7, to: start)!,
        days: [day],
        minimum: 40 * 3600,
        maximum: 45 * 3600,
        remainingCapacity: 0,
        scheduledCapacity: 40 * 3600,
        projection: nil,
        projectionLow: nil,
        projectionHigh: nil,
        usableDays: 1)
}

@Test func discordPresenceCopyMapsStatusAndTotals() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let week = sampleWeek(calendar: calendar)
    let formatted = DiscordPresenceCopy.format(
        indicator: .passive,
        todayProductive: 5400,
        week: week,
        calendar: calendar,
        showDaily: true,
        showWeekly: true,
        showBreakdown: false,
        trackingStartedAt: nil)
    #expect(formatted?.details == "Worktempo: Passive 🔵")
    #expect(formatted?.state == "1h 30m today  ·  1h 30m this week")
    #expect(formatted?.smallImageKey == "status_passive")
}

@Test func discordPresenceCopyOmitsHiddenState() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    #expect(DiscordPresenceCopy.format(
        indicator: .hidden,
        todayProductive: 0,
        week: sampleWeek(calendar: calendar),
        calendar: calendar,
        showDaily: true,
        showWeekly: true,
        showBreakdown: true,
        trackingStartedAt: nil) == nil)
}

@Test func discordPresenceCopyBreakdownInLargeImageText() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let formatted = DiscordPresenceCopy.format(
        indicator: .active,
        todayProductive: 0,
        week: sampleWeek(calendar: calendar),
        calendar: calendar,
        showDaily: false,
        showWeekly: false,
        showBreakdown: true,
        trackingStartedAt: nil)
    #expect(formatted?.largeImageText.hasPrefix("This week — ") == true)
    #expect(formatted?.largeImageText.contains("1h 30m") == true)
    #expect(formatted?.details == "Worktempo: Active 🟢")
}
