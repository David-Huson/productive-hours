import Foundation
import Testing
@testable import ActivityCore

private func callEngine() -> TrackingEngine {
    var engine = TrackingEngine(start: 0)
    _ = engine.apply(.pause(false), at: 0)
    _ = engine.apply(.foreground(Source(app: "other", productivity: .unproductive)), at: 0)
    _ = engine.apply(.observedIdle(600_000), at: 0)
    _ = engine.apply(.recovered, at: 0)
    return engine
}
private let zoom = Source(app: "us.zoom.xos", productivity: .productive)

@Test func listeningCallCountsBeyondIdleLimitAndStopsWithoutResettingInput() {
    var engine = callEngine()
    var rows = engine.apply(.call(zoom), at: 0)
    for time in stride(from: Int64(5_000), through: 600_000, by: 5_000) {
        rows += engine.apply(.call(zoom), at: time)
    }
    rows += engine.apply(.call(nil), at: 600_000)
    rows += engine.apply(.tick, at: 620_000)
    #expect(rows.filter(\.productive).reduce(0) { $0 + $1.seconds } == 600)
    #expect(rows.filter(\.productive).allSatisfy { $0.activity == .passive && $0.reason == "call_audio" && $0.source.app == zoom.app })
    #expect(engine.lastInput == -600_000)
    #expect(engine.state == .inactive)
    #expect(zip(rows, rows.dropFirst()).allSatisfy { $0.end == $1.start })
}

@Test func missingCallSamplesExpireAtExactBoundary() {
    var engine = callEngine()
    _ = engine.apply(.call(zoom), at: 0)
    let rows = engine.apply(.tick, at: 60_000)
    #expect(rows.map(\.seconds) == [10, 50])
    #expect(rows.map(\.productive) == [true, false])
    #expect(rows.last?.source.app == "other")
}

@Test func callsNeverOverrideBarriersPauseOrFailure() {
    for event in [TrackingEvent.barrier("sleep", true), .barrier("session", true), .pause(true), .failure] {
        var engine = callEngine()
        _ = engine.apply(.call(zoom), at: 0)
        _ = engine.apply(event, at: 1_000)
        _ = engine.apply(.call(zoom), at: 1_000)
        #expect(engine.apply(.tick, at: 5_000).allSatisfy { !$0.productive })
    }
}

@Test func callRecoveryAndOldCheckpointCompatibility() throws {
    var engine = callEngine()
    _ = engine.apply(.call(zoom), at: 0)
    let data = try JSONEncoder().encode(engine)
    var restored = try JSONDecoder().decode(TrackingEngine.self, from: data)
    #expect(restored.recover(at: 60_000).allSatisfy { !$0.productive && $0.activity == .unknown })
    #expect(restored.call == nil)
    var legacy = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    legacy.removeValue(forKey: "call")
    let old = try JSONDecoder().decode(TrackingEngine.self, from: JSONSerialization.data(withJSONObject: legacy))
    #expect(old.call == nil)
}

@Test func privateAndIgnoredForegroundPreventCallCredit() {
    for source in [Source(app: "private", productivity: .productive, privateBrowsing: true), Source(app: "ignored", productivity: .ignored)] {
        var engine = callEngine()
        _ = engine.apply(.foreground(source), at: 0)
        _ = engine.apply(.call(zoom), at: 0)
        #expect(engine.apply(.tick, at: 5_000).allSatisfy { !$0.productive })
    }
}

@Test func simultaneousForegroundWorkAndCallCountOnlyOnce() {
    var engine = callEngine()
    _ = engine.apply(.input, at: 0)
    _ = engine.apply(.foreground(Source(app: "ide", productivity: .productive)), at: 0)
    _ = engine.apply(.call(zoom), at: 0)
    let rows = engine.apply(.tick, at: 5_000)
    #expect(rows.reduce(0) { $0 + $1.seconds } == 5)
    #expect(rows.filter(\.productive).reduce(0) { $0 + $1.seconds } == 5)
    #expect(rows.allSatisfy { $0.activity == .active && $0.source.app == zoom.app })
}
