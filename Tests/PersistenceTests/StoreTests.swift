import Foundation
import Testing
import ActivityCore
@testable import Persistence

private func location() -> URL { FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).appending(path: "test.sqlite") }
@Test func callCreditSurvivesReopenAndOrdinaryRuleReclassification() throws {
    let url = location(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    var engine = TrackingEngine(start: 0)
    _ = engine.apply(.pause(false), at: 0)
    _ = engine.apply(.observedIdle(600_000), at: 0)
    _ = engine.apply(.recovered, at: 0)
    _ = engine.apply(.call(Source(app: "us.zoom.xos", productivity: .productive)), at: 0)
    let rows = engine.apply(.tick, at: 5_000)
    do { let store = try Store(url: url); try store.commit(rows, checkpoint: engine) }
    let store = try Store(url: url)
    try store.reclassify(rules: [], previousRules: [], at: Date())
    #expect(try store.intervals() == rows)
    var restored = try #require(try store.load("checkpoint", as: TrackingEngine.self))
    #expect(restored.recover(at: 60_000).allSatisfy { !$0.productive })
}
@Test func durableCheckpointAndIdempotentRetry() throws {
    let url = location(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    var engine = TrackingEngine(start: 0); _ = engine.apply(.tick, at: 30_000)
    let row = Interval(start: 0, end: 30_000, source: Source(app: "ide", productivity: .productive), activity: .passive)
    do { let store = try Store(url: url); try store.commit([row], checkpoint: engine); try store.commit([row], checkpoint: engine) }
    let restored = try Store(url: url)
    #expect(try restored.intervals() == [row])
    #expect(try restored.load("checkpoint", as: TrackingEngine.self)?.boundary == 30_000)
}
@Test func overlapRollsBackBothRowsAndCheckpoint() throws {
    let url = location(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let store = try Store(url: url)
    var engine = TrackingEngine(start: 0); _ = engine.apply(.tick, at: 10)
    try store.commit([Interval(start: 0, end: 10, source: Source(), activity: .unknown)], checkpoint: engine)
    _ = engine.apply(.tick, at: 30)
    #expect(throws: (any Error).self) {
        try store.commit([Interval(start: 10, end: 20, source: Source(), activity: .active), Interval(start: 5, end: 30, source: Source(), activity: .passive)], checkpoint: engine)
    }
    #expect(try store.intervals().count == 1)
    #expect(try store.load("checkpoint", as: TrackingEngine.self)?.boundary == 10)
}
@Test func classificationRoundtripPreviewUndoAndRetention() throws {
    let url = location(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let store = try Store(url: url)
    var engine = TrackingEngine(start: 0); _ = engine.apply(.tick, at: 1000)
    try store.commit([Interval(start: 0, end: 1000, source: Source(app: "ide", productivity: .unproductive), activity: .passive)], checkpoint: engine)
    let rules = [ClassificationRule(kind: .app, pattern: "ide", productivity: .productive)]
    try store.reclassify(rules: rules, previousRules: [], at: Date())
    #expect(try store.intervals().first?.productive == true)
    _ = try store.undoReclassification()
    #expect(try store.intervals().first?.source.productivity == .unproductive)
    try store.retain(settings: AppSettings(), now: Date(timeIntervalSince1970: 100 * 86400))
    #expect(try store.intervals().isEmpty)
    #expect(try store.archives().first?.total.unproductive == 1)
    try store.deleteAll()
    #expect(try store.archives().isEmpty)
    #expect(try store.load("checkpoint", as: TrackingEngine.self) == nil)
}
@Test func corruptedDatabaseIsNotSilentlyReplaced() throws {
    let url = location(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let corrupt = Data("not sqlite".utf8); try corrupt.write(to: url)
    #expect(throws: (any Error).self) { try Store(url: url) }
    #expect(try Data(contentsOf: url) == corrupt)
}

@Test func eightHourSessionSurvivesHourlyReopen() throws {
    let url = location(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    var engine = TrackingEngine(start: 0)
    _ = engine.apply(.pause(false), at: 0); _ = engine.apply(.recovered, at: 0)
    var pending: [Interval] = []
    for minute in 0..<480 {
        let time = Int64(minute * 60_000)
        pending += engine.apply(.input, at: time)
        let category: ProductivityClass = minute % 15 < 10 ? .productive : .unproductive
        pending += engine.apply(.foreground(Source(app: "fixture", productivity: category)), at: time)
        pending += engine.apply(.tick, at: time + 60_000)
        if (minute + 1) % 60 == 0 {
            do { let store = try Store(url: url); try store.commit(pending, checkpoint: engine) }
            pending = []
            let reopened = try Store(url: url)
            engine = try #require(try reopened.load("checkpoint", as: TrackingEngine.self))
        }
    }
    let store = try Store(url: url)
    let rows = try store.intervals()
    #expect(rows.reduce(0) { $0 + $1.seconds } == 8 * 3600)
    #expect(rows.filter(\.productive).reduce(0) { $0 + $1.seconds } == 320 * 60)
    #expect(zip(rows, rows.dropFirst()).allSatisfy { $0.end == $1.start })
}

@Test func forwardRuleHistoryAndReferenceCorrectionsSurviveReopen() throws {
    let url = location(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let original = ReferenceTotal(day: "2026-10-30", timezone: "UTC", metric: "Productive", seconds: 3600, source: "manual")
    let correction = ReferenceTotal(day: original.day, timezone: "UTC", metric: "Productive", seconds: 7200, source: "manual", correctsID: original.id)
    do {
        let store = try Store(url: url)
        try store.saveRuleSet([ClassificationRule(kind: .app, pattern: "ide", productivity: .productive)])
        try store.importReferences([original, correction])
    }
    let store = try Store(url: url)
    #expect(try store.ruleRevisions().count == 1)
    #expect(try store.references().count == 2)
    #expect(try store.references().contains { $0.correctsID == original.id })
}

@Test func privateBrowsingCannotBeMadeProductiveByHistoricalRuleChanges() throws {
    let url = location(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let store = try Store(url: url)
    var engine = TrackingEngine(start: 0); _ = engine.apply(.tick, at: 1000)
    let source = Source(app: "chrome", productivity: .ignored, privateBrowsing: true)
    try store.commit([Interval(start: 0, end: 1000, source: source, activity: .passive)], checkpoint: engine)
    try store.reclassify(rules: [ClassificationRule(kind: .app, pattern: "chrome", productivity: .productive)], previousRules: [], at: Date())
    #expect(try store.intervals().first?.productive == false)
    #expect(try store.intervals().first?.source.privateBrowsing == true)
}
