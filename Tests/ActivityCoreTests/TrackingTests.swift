import Foundation
import Testing
@testable import ActivityCore

private func prepared() -> TrackingEngine {
    var engine = TrackingEngine(start: 0)
    _ = engine.apply(.pause(false), at: 0)
    _ = engine.apply(.foreground(Source(app: "ide", productivity: .productive)), at: 0)
    _ = engine.apply(.input, at: 0)
    _ = engine.apply(.recovered, at: 0)
    return engine
}
@Test func reducerNineMinuteAcceptance() {
    var engine = prepared()
    let rows = engine.apply(.tick, at: 540_000)
    #expect(rows.map(\.activity) == [.active, .passive, .inactive])
    #expect(rows.map(\.seconds) == [120, 300, 120])
    #expect(rows.filter(\.productive).reduce(0) { $0 + $1.seconds } == 420)
}
@Test func foregroundSwitchDoesNotResetIdle() {
    var engine = prepared()
    var rows = engine.apply(.foreground(Source(app: "leisure", productivity: .unproductive)), at: 180_000)
    rows += engine.apply(.tick, at: 540_000)
    #expect(rows.filter(\.productive).reduce(0) { $0 + $1.seconds } == 180)
    #expect(rows.last?.activity == .inactive)
    #expect(engine.lastInput == 0)
}
@Test func sleepAndNestedBarriersPreventCredit() {
    var engine = prepared()
    var rows = engine.apply(.barrier("sleep", true), at: 10_000)
    rows += engine.apply(.barrier("display", true), at: 11_000)
    rows += engine.apply(.barrier("display", false), at: 12_000)
    #expect(engine.state == .inactive)
    rows += engine.apply(.barrier("sleep", false), at: 10_810_000)
    #expect(engine.state == .unknown)
    #expect(rows.filter(\.productive).reduce(0) { $0 + $1.seconds } == 10)
}
@Test func crashRecoveryNeverCreditsDowntime() throws {
    var engine = prepared()
    _ = engine.apply(.tick, at: 30_000)
    let data = try JSONEncoder().encode(engine)
    var restored = try JSONDecoder().decode(TrackingEngine.self, from: data)
    let rows = restored.recover(at: 2_730_000)
    #expect(rows.allSatisfy { $0.activity == .unknown })
    #expect(rows.reduce(0) { $0 + $1.seconds } == 2700)
}
@Test func repeatedAndOutOfOrderEventsCannotCreateNegativeTime() {
    var engine = prepared()
    _ = engine.apply(.tick, at: 30_000)
    #expect(engine.apply(.input, at: 20_000).isEmpty)
    #expect(engine.lastInput == 0)
    #expect(engine.apply(.tick, at: 30_000).isEmpty)
}
@Test func generatedWeekHasNoOverlapOrExcessCredit() {
    var engine = prepared()
    var rows: [Interval] = []
    var seed: UInt64 = 12345
    var time: Int64 = 0
    for _ in 0..<20_000 {
        seed = seed &* 6364136223846793005 &+ 1
        time += Int64(seed % 60_000 + 1)
        let event: TrackingEvent
        switch seed % 7 {
        case 0: event = .input
        case 1: event = .foreground(Source(app: "other", productivity: .unproductive))
        case 2: event = .foreground(Source(app: "ide", productivity: .productive))
        case 3: event = .barrier("sleep", true)
        case 4: event = .barrier("sleep", false)
        case 5: event = .recovered
        default: event = .tick
        }
        rows += engine.apply(event, at: time)
    }
    #expect(rows.allSatisfy { $0.end > $0.start })
    #expect(zip(rows, rows.dropFirst()).allSatisfy { $0.end == $1.start })
    #expect(rows.reduce(Int64(0)) { $0 + $1.end - $1.start } == time)
    #expect(rows.filter(\.productive).reduce(Int64(0)) { $0 + $1.end - $1.start } <= time)
}
@Test func pauseIsUnknownAndNeedsFreshObservation() {
    var engine = prepared()
    _ = engine.apply(.pause(true), at: 10_000)
    let rows = engine.apply(.pause(false), at: 100_000)
    #expect(rows.allSatisfy { $0.activity == .unknown && !$0.productive })
    #expect(engine.state == .unknown)
}
