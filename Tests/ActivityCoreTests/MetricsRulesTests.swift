import Foundation
import Testing
@testable import ActivityCore

private func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
@Test func activityLabelUsesStoredHostRuleDisplayName() {
    let github = ClassificationRule(
        kind: .exactHost,
        pattern: "github.com",
        productivity: .productive,
        displayName: "Github"
    )
    let chrome = ClassificationRule(
        kind: .app,
        pattern: "com.google.Chrome",
        productivity: .productive,
        displayName: "Chrome"
    )
    let rules = [chrome, github]
    let source = Source(
        app: "com.google.Chrome",
        host: "github.com",
        productivity: .productive,
        ruleID: github.id,
        ruleVersion: 1
    )
    #expect(ActivityLabel.label(for: source, rules: rules) == "Github")
}

@Test func activityLabelShowsHostnameForBrowserAppFallback() {
    let chrome = ClassificationRule(
        kind: .app,
        pattern: "com.google.Chrome",
        productivity: .productive,
        displayName: "Chrome"
    )
    let source = Source(
        app: "com.google.Chrome",
        host: "chatgpt.com",
        productivity: .productive,
        ruleID: chrome.id,
        ruleVersion: 1
    )
    #expect(ActivityLabel.label(for: source, rules: [chrome]) == "chatgpt.com")
}

@Test func ruleLabelPrefersDisplayName() {
    var rule = ClassificationRule(kind: .app, pattern: "com.todesktop.230313mzl4w4u92", productivity: .productive)
    #expect(rule.label == "com.todesktop.230313mzl4w4u92")
    rule.displayName = "Cursor"
    #expect(rule.label == "Cursor")
    rule.displayName = "  "
    #expect(rule.label == "com.todesktop.230313mzl4w4u92")
}

@Test func hostPrecedenceAndExclusionOverrideBrowser() {
    let rules = [
        ClassificationRule(kind: .app, pattern: "chrome", productivity: .productive),
        ClassificationRule(kind: .domain, pattern: "example.com", productivity: .unproductive),
        ClassificationRule(kind: .subdomains, pattern: "work.example.com", productivity: .productive),
        ClassificationRule(kind: .exactHost, pattern: "private.work.example.com", productivity: .ignored)
    ]
    #expect(RuleEvaluator.resolve(app: "chrome", host: "private.work.example.com", rules: rules).productivity == .ignored)
    #expect(RuleEvaluator.resolve(app: "chrome", host: "a.work.example.com", rules: rules).productivity == .productive)
    #expect(RuleEvaluator.resolve(app: "chrome", host: "example.com", rules: rules).productivity == .unproductive)
    #expect(RuleEvaluator.resolve(app: "chrome", host: "notexample.com", rules: rules).productivity == .productive)
    #expect(RuleEvaluator.resolve(app: "chrome", host: nil, rules: rules).productivity == .productive)
    #expect(RuleEvaluator.resolve(app: "chrome", host: nil, rules: []).productivity == .undefined)
    #expect(RuleEvaluator.hostname("https://example.com/private") == nil)
}
@Test func crossWeekSplitsExactly() {
    var settings = AppSettings(); settings.timezone = "UTC"
    let start = date("2026-10-25T23:50:00Z"), end = date("2026-10-26T00:10:00Z")
    let totals = Metrics.aggregate([Interval(start: start.epochMS, end: end.epochMS, source: Source(productivity: .productive), activity: .active)], settings: settings)
    #expect(totals.count == 2)
    #expect(totals.map(\.productive) == [600, 600])
    #expect(Metrics.week(containing: start, now: end, totals: totals, settings: settings).productive == 600)
    #expect(Metrics.week(containing: end, now: end, totals: totals, settings: settings).productive == 600)
}
@Test(arguments: [("2026-03-08T06:00:00Z", "2026-03-09T05:00:00Z", 23.0), ("2026-11-01T05:00:00Z", "2026-11-02T06:00:00Z", 25.0)])
func dstPreservesElapsedTime(start: String, end: String, hours: Double) {
    var settings = AppSettings(); settings.timezone = "America/Chicago"
    let totals = Metrics.aggregate([Interval(start: date(start).epochMS, end: date(end).epochMS, source: Source(productivity: .productive), activity: .passive)], settings: settings)
    #expect(totals.count == 1)
    #expect(totals[0].productive == hours * 3600)
}
@Test(arguments: [(24.5, 10.5, 15.5, 0.0), (34, 1, 6, 0), (38, 0, 2, 0), (41, 0, 0, 1)])
func targetAcceptance(hours: Double, remaining: Double, headroom: Double, overage: Double) {
    var settings = AppSettings(); settings.timezone = "UTC"
    let now = date("2026-10-30T18:00:00Z")
    var total = DayTotal(id: "2026-10-30", date: date("2026-10-30T00:00:00Z")); total.active = hours * 3600
    let week = Metrics.week(containing: now, now: now, totals: [total], settings: settings)
    #expect(week.remaining == remaining * 3600)
    #expect(week.headroom == headroom * 3600)
    #expect(week.overage == overage * 3600)
    #expect(week.remainingCapacity == 0)
}
@Test func forecastUsesOnlyRemainingScheduleAndRequiresThreeDays() {
    var settings = AppSettings(); settings.timezone = "UTC"
    let now = date("2026-10-28T13:00:00Z")
    let rows = (26...28).map { day in
        let start = date("2026-10-\(day)T09:00:00Z")
        return Interval(start: start.epochMS, end: start.addingTimeInterval(4 * 3600).epochMS, source: Source(productivity: .productive), activity: .active)
    }
    let totals = Metrics.aggregate(rows, settings: settings)
    let week = Metrics.week(containing: now, now: now, totals: totals, settings: settings)
    #expect(week.remainingCapacity == 20 * 3600)
    #expect(abs((week.projection ?? 0) - 32 * 3600) < 0.001)
    #expect(Metrics.week(containing: now, now: now, totals: Array(totals.prefix(2)), settings: settings).projection == nil)
}
