import Foundation
import Testing
@testable import ActivityCore

@Test func calibrationFiveDaySampleAndCorrection() throws {
    let csv = "date,productive_seconds,unnecessary\n2026-10-26,3600,discard\n2026-10-27,7200,discard\n2026-10-28,10800,discard\n2026-10-29,14400,discard\n2026-10-30,18000,discard\n"
    var references = try CalibrationCSV.parse(csv, timezone: "UTC", metric: "Productive")
    #expect(references.count == 5)
    let days = references.map { ref in
        var day = DayTotal(id: ref.day, date: Date()); day.active = ref.seconds + 600; return day
    }
    let summary = ComparisonSummary.calculate(references: references, days: days, metric: "Productive", timezone: "UTC")
    #expect(summary.count == 5)
    #expect(summary.delta == 3000)
    #expect(summary.medianAbsoluteDailyError == 600)
    references.append(ReferenceTotal(day: references[0].day, timezone: "UTC", metric: "Productive", seconds: 4200, source: "manual", correctsID: references[0].id))
    #expect(ComparisonSummary.calculate(references: references, days: days, metric: "Productive", timezone: "UTC").delta == 2400)
}
@Test(arguments: ["bad,header\n1,2", "date,productive_seconds\n2026-02-30,5", "date,productive_seconds\n2026-10-30,nan", "date,productive_seconds\n2026-10-30,5\n2026-10-30,5", "date,productive_seconds\n\"unclosed"])
func invalidCSVRejected(csv: String) {
    #expect(throws: CSVError.self) { try CalibrationCSV.parse(csv, timezone: "UTC", metric: "Productive") }
}
@Test func alertRequiresSustainedProjectionAndResetsOnCrossing() {
    var state = ForecastAlertState(); let now = Date(timeIntervalSince1970: 0)
    #expect(state.evaluate(projection: 30, minimum: 35, maximum: 40, now: now) == nil)
    #expect(state.evaluate(projection: 30, minimum: 35, maximum: 40, now: now.addingTimeInterval(1799)) == nil)
    #expect(state.evaluate(projection: 30, minimum: 35, maximum: 40, now: now.addingTimeInterval(1800)) == "behind_weekly_pace")
    #expect(state.evaluate(projection: 38, minimum: 35, maximum: 40, now: now.addingTimeInterval(1801)) == nil)
    #expect(state.evaluate(projection: 30, minimum: 35, maximum: 40, now: now.addingTimeInterval(1802)) == nil)
    #expect(state.evaluate(projection: nil, minimum: 35, maximum: 40, now: now.addingTimeInterval(4000)) == nil)
}
@Test func alertsRespectQuietHoursCooldownAndSnooze() {
    var settings = AppSettings(); settings.timezone = "UTC"; settings.notifications = true
    let now = ISO8601DateFormatter().date(from: "2026-10-30T17:00:00Z")!
    #expect(NotificationPolicy.canDeliver(now: now, settings: settings, lastSent: nil, snoozedUntil: nil))
    #expect(!NotificationPolicy.canDeliver(now: now.addingTimeInterval(3600), settings: settings, lastSent: nil, snoozedUntil: nil))
    #expect(!NotificationPolicy.canDeliver(now: now, settings: settings, lastSent: now.addingTimeInterval(-3600), snoozedUntil: nil))
    #expect(!NotificationPolicy.canDeliver(now: now, settings: settings, lastSent: nil, snoozedUntil: now.addingTimeInterval(3600)))
}
