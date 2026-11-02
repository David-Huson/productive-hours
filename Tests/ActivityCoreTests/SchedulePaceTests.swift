import Foundation
import Testing
@testable import ActivityCore

private func moment(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
private func pace(_ now: String, hours: Double, settings: AppSettings) -> WeeklyMetrics {
    let date = moment(now)
    let day = settings.calendar.startOfDay(for: date)
    var total = DayTotal(id: Metrics.dayKey(day, calendar: settings.calendar), date: day)
    total.active = hours * 3600
    return Metrics.week(containing: date, now: date, totals: [total], settings: settings)
}

@Test func schedulePaceWorksWithoutForecastAndUsesAdjustedTarget() {
    var settings = AppSettings(); settings.timezone = "UTC"
    settings.minimumHours = 30; settings.maximumHours = 35
    let week = pace("2026-11-02T13:00:00Z", hours: 3.25, settings: settings)
    #expect(abs(week.expectedMinimum - 3 * 3600) < 0.001)
    #expect(abs(week.expectedMaximum - 3.5 * 3600) < 0.001)
    #expect(week.projection == nil)
    #expect(week.status == "On track")
    #expect(pace("2026-11-02T13:00:00Z", hours: 2, settings: settings).status == "Behind pace")
    #expect(pace("2026-11-02T13:00:00Z", hours: 4, settings: settings).status == "Above pace")
}

@Test func fortyHourPaceMatchesDayAndPartialDaySchedule() {
    var settings = AppSettings(); settings.timezone = "UTC"
    settings.minimumHours = 40; settings.maximumHours = 40
    for (now, hours) in [("2026-11-02T17:00:00Z", 8.0), ("2026-11-03T17:00:00Z", 16.0), ("2026-11-04T13:00:00Z", 20.0)] {
        let week = pace(now, hours: hours, settings: settings)
        #expect(abs(week.expectedMinimum - hours * 3600) < 0.001)
        #expect(week.status == "On track")
    }
    #expect(pace("2026-11-02T13:00:00Z", hours: 4 - 30.0 / 3600, settings: settings).status == "On track")
}

@Test func paceHandlesScheduleBoundariesAndNoWorkdays() {
    var settings = AppSettings(); settings.timezone = "UTC"
    #expect(pace("2026-11-02T08:00:00Z", hours: 0, settings: settings).status == "Schedule not started")
    #expect(pace("2026-11-07T12:00:00Z", hours: 36, settings: settings).status == "Target met")
    #expect(pace("2026-11-07T12:00:00Z", hours: 30, settings: settings).status == "Below target")
    #expect(pace("2026-11-07T12:00:00Z", hours: 41, settings: settings).status == "Above target")
    settings.workdays = []
    #expect(pace("2026-11-02T13:00:00Z", hours: 0, settings: settings).status == "Set work schedule")
}

@Test func paceRespectsTimezoneAndCustomWorkdays() {
    var settings = AppSettings(); settings.timezone = "America/Chicago"
    settings.workdays = [3, 5]; settings.minimumHours = 12; settings.maximumHours = 16
    let week = pace("2026-11-03T19:00:00Z", hours: 3.5, settings: settings)
    #expect(week.scheduledCapacity == 16 * 3600)
    #expect(week.expectedMinimum == 3 * 3600)
    #expect(week.expectedMaximum == 4 * 3600)
    #expect(week.status == "On track")
}

@Test func burnupSeparatesPlannedFutureFromObservedActuals() {
    var settings = AppSettings(); settings.timezone = "UTC"
    settings.minimumHours = 35; settings.maximumHours = 40
    let now = moment("2026-11-02T13:00:00Z")
    let week = pace("2026-11-02T13:00:00Z", hours: 3, settings: settings)
    let series = Metrics.burnup(week: week, now: now, settings: settings)
    #expect(series.actual.last?.date == now)
    #expect(series.actual.last?.seconds == 10800.0)
    #expect(series.actual.allSatisfy { $0.date <= now })
    #expect(series.planned.first { $0.date == moment("2026-11-02T17:00:00Z") }?.seconds == 28800.0)
    #expect(series.planned.first { $0.date == moment("2026-11-03T09:00:00Z") }?.seconds == 28800.0)
    #expect(series.planned.last?.seconds == 144000.0)
    #expect(Metrics.burnup(week: week, now: week.start.addingTimeInterval(-1), settings: settings).actual.isEmpty)
}
