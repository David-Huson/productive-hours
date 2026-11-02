import Testing
@testable import ActivityCore

@Test func nineMinuteIdleIsExactlyTwoFiveTwo() throws {
    let slices = try IdlePolicy().slices(from: 0, to: 540_000)
    #expect(slices.map(\.state) == [.active, .passive, .inactive])
    #expect(slices.map(\.duration) == [120_000, 300_000, 120_000])
}

@Test(arguments: [(Int64(0), ActivityState.active), (119_999, .active),
                  (120_000, .passive), (419_999, .passive), (420_000, .inactive)])
func halfOpenThresholds(idle: Int64, expected: ActivityState) throws {
    #expect(try IdlePolicy().state(idleMilliseconds: idle) == expected)
}

@Test func unavailableIdleIsUnknown() throws {
    let policy = try IdlePolicy()
    #expect(policy.state(idleMilliseconds: nil) == .unknown)
    #expect(policy.state(idleMilliseconds: -1) == .unknown)
}

@Test func invalidThresholdsAreRejected() {
    #expect(throws: IdlePolicy.ValidationError.self) { try IdlePolicy(activeMilliseconds: 0) }
    #expect(throws: IdlePolicy.ValidationError.self) { try IdlePolicy(passiveMilliseconds: -1) }
    #expect(throws: IdlePolicy.ValidationError.self) { try IdlePolicy(activeMilliseconds: .max) }
}

@Test func zeroPassiveDurationHasNoEmptySlice() throws {
    let slices = try IdlePolicy(passiveMilliseconds: 0).slices(from: 0, to: 180_000)
    #expect(slices.map(\.state) == [.active, .inactive])
    #expect(slices.allSatisfy { $0.duration > 0 })
}

@Test func reversedAndEmptyRangesProduceNoCredit() throws {
    let policy = try IdlePolicy()
    #expect(policy.slices(from: 20, to: 10).isEmpty)
    #expect(policy.slices(from: 10, to: 10).isEmpty)
    #expect(policy.slices(from: -1, to: 10).isEmpty)
}

@Test func arbitrarySamplingCadencePreservesElapsedTime() throws {
    let policy = try IdlePolicy()
    var totals: [ActivityState: Int64] = [:]
    var cursor: Int64 = 0
    while cursor < 540_000 {
        let end = min(cursor + 7_333, 540_000)
        let slices = policy.slices(from: cursor, to: end)
        #expect(slices.first?.start == cursor)
        #expect(slices.last?.end == end)
        #expect(slices.reduce(0) { $0 + $1.duration } == end - cursor)
        for slice in slices { totals[slice.state, default: 0] += slice.duration }
        cursor = end
    }
    #expect(totals[.active] == 120_000)
    #expect(totals[.passive] == 300_000)
    #expect(totals[.inactive] == 120_000)
}

@Test func overnightIdleDoesNotExtendCreditedWindow() throws {
    let slices = try IdlePolicy().slices(from: 0, to: 86_400_000)
    #expect(slices.filter { $0.state != .inactive }.reduce(0) { $0 + $1.duration } == 420_000)
}

@Test func clockContinuityDistinguishesGapsFromClockChanges() {
    var clock = ClockContinuity()
    #expect(clock.observe(.init(wallMilliseconds: 0, monotonicMilliseconds: 0)) == .initial)
    #expect(clock.observe(.init(wallMilliseconds: 5_000, monotonicMilliseconds: 5_000)) == .continuous)
    #expect(clock.observe(.init(wallMilliseconds: 50_000, monotonicMilliseconds: 50_000)) == .collectionGap)
    #expect(clock.observe(.init(wallMilliseconds: 45_000, monotonicMilliseconds: 55_000)) == .clockAnomaly)
    #expect(clock.observe(.init(wallMilliseconds: 100_000, monotonicMilliseconds: 60_000)) == .clockAnomaly)
    #expect(clock.observe(.init(wallMilliseconds: 105_000, monotonicMilliseconds: 65_000)) == .continuous)
}

@Test func clockOverflowAndMonotonicResetAreAnomalies() {
    var clock = ClockContinuity()
    _ = clock.observe(.init(wallMilliseconds: .min, monotonicMilliseconds: 10))
    #expect(clock.observe(.init(wallMilliseconds: .max, monotonicMilliseconds: 20)) == .clockAnomaly)
    #expect(clock.observe(.init(wallMilliseconds: .max, monotonicMilliseconds: 0)) == .clockAnomaly)
}
