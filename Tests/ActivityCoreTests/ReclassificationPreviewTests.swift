import Foundation
import Testing
@testable import ActivityCore

@Test func discordRuleRoundTripInvalidatesOldPreviewAndRestoresProductiveTime() {
    var discord = ClassificationRule(kind: .app, pattern: "com.hnc.Discord", productivity: .productive)
    let row = Interval(start: 0, end: 7_200_000,
        source: RuleEvaluator.resolve(app: discord.pattern, host: nil, rules: [discord]), activity: .active)
    discord.productivity = .undefined; discord.version += 1
    let first = ReclassificationPreview(intervals: [row], rules: [discord])
    #expect(first.after - first.before == -7200)
    discord.productivity = .productive; discord.version += 1
    #expect(!first.matches(rules: [discord]))
    let second = ReclassificationPreview(intervals: [row], rules: [discord])
    #expect(second.before == 7200)
    #expect(second.after == 7200)
    #expect(second.changes.isEmpty)
    #expect(row.productive) // Preview never mutates retained history.
}

@Test func previewExplainsOtherSourceLossWhenDiscordIsProductive() {
    let discord = ClassificationRule(kind: .app, pattern: "com.hnc.Discord", productivity: .productive)
    let rows = [
        Interval(start: 0, end: 7_200_000, source: Source(app: discord.pattern, productivity: .productive), activity: .active),
        Interval(start: 7_200_000, end: 14_400_000, source: Source(app: "com.google.Chrome", host: "example.com", productivity: .productive), activity: .active)
    ]
    let preview = ReclassificationPreview(intervals: rows, rules: [discord])
    #expect(preview.after - preview.before == -7200)
    #expect(preview.changes.count == 1)
    #expect(preview.changes.first?.source.host == "example.com")
    #expect(preview.changes.first?.delta == -7200)
}

@Test func previewAndAppliedRowsUseIdenticalCallPrivacyAndIdleRules() {
    let rows = [
        Interval(start: 0, end: 1000, source: Source(app: "call", productivity: .productive), activity: .passive, reason: "call_audio"),
        Interval(start: 1000, end: 2000, source: Source(app: "browser", productivity: .ignored, privateBrowsing: true), activity: .active),
        Interval(start: 2000, end: 3000, source: Source(app: "editor", productivity: .productive), activity: .inactive)
    ]
    let rules = [ClassificationRule(kind: .app, pattern: "browser", productivity: .productive)]
    let preview = ReclassificationPreview(intervals: rows, rules: rules)
    let applied = rows.map { ReclassificationPreview.reclassified($0, rules: rules) }
    #expect(preview.after == applied.filter(\.productive).reduce(0) { $0 + $1.seconds })
    #expect(preview.after == 1)
    #expect(applied[0] == rows[0])
    #expect(applied[1] == rows[1])
}

@Test func unclassifiedWebsiteRetainsExplicitBrowserFallbackDuringRecalculation() {
    let arc = ClassificationRule(kind: .app, pattern: "company.thebrowser.Browser", productivity: .productive)
    let rows = [Interval(start: 0, end: 4_444_000,
        source: Source(app: arc.pattern, host: "app.datadoghq.com", productivity: .productive, ruleID: arc.id, ruleVersion: arc.version), activity: .active)]
    let preview = ReclassificationPreview(intervals: rows, rules: [arc])
    #expect(preview.after == 4444)
    #expect(preview.changes.isEmpty)
    let explicit = ClassificationRule(kind: .domain, pattern: "datadoghq.com", productivity: .undefined)
    #expect(ReclassificationPreview(intervals: rows, rules: [arc, explicit]).after == 0)
    #expect(ReclassificationPreview(intervals: rows, rules: []).after == 0)
}
