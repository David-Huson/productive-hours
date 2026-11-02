/// Phase 0 observation values. These are diagnostics, not a productive-time ledger.
public enum ActivityState: String, Codable, Sendable {
    case active, passive, inactive, unknown
}

public struct IdlePolicy: Sendable {
    public let activeMilliseconds: Int64
    public let passiveMilliseconds: Int64

    public init(activeMilliseconds: Int64 = 120_000, passiveMilliseconds: Int64 = 300_000) throws {
        guard activeMilliseconds > 0, passiveMilliseconds >= 0,
              !activeMilliseconds.addingReportingOverflow(passiveMilliseconds).overflow else {
            throw ValidationError.invalidThresholds
        }
        self.activeMilliseconds = activeMilliseconds
        self.passiveMilliseconds = passiveMilliseconds
    }

    public func state(idleMilliseconds: Int64?) -> ActivityState {
        guard let idleMilliseconds, idleMilliseconds >= 0 else { return .unknown }
        if idleMilliseconds < activeMilliseconds { return .active }
        if idleMilliseconds < activeMilliseconds + passiveMilliseconds { return .passive }
        return .inactive
    }

    /// Exact threshold slicing, independent of timer cadence. Offsets start at last input.
    public func slices(from start: Int64, to end: Int64) -> [IdleSlice] {
        guard start >= 0, end > start else { return [] }
        let boundaries = [start, activeMilliseconds, activeMilliseconds + passiveMilliseconds, end]
            .filter { $0 >= start && $0 <= end }
        let ordered = Set(boundaries).sorted()
        return zip(ordered, ordered.dropFirst()).map {
            IdleSlice(start: $0, end: $1, state: state(idleMilliseconds: $0))
        }
    }

    public enum ValidationError: Error { case invalidThresholds }
}

public struct IdleSlice: Equatable, Sendable {
    public let start: Int64
    public let end: Int64
    public let state: ActivityState
    public var duration: Int64 { end - start }
}

public struct ClockSample: Sendable {
    public let wallMilliseconds: Int64
    public let monotonicMilliseconds: Int64
    public init(wallMilliseconds: Int64, monotonicMilliseconds: Int64) {
        self.wallMilliseconds = wallMilliseconds
        self.monotonicMilliseconds = monotonicMilliseconds
    }
}

public enum ObservationHealth: String, Codable, Sendable {
    case initial, continuous, clockAnomaly, collectionGap
}

public struct ClockContinuity: Sendable {
    private var previous: ClockSample?
    public init() {}

    public mutating func observe(_ sample: ClockSample) -> ObservationHealth {
        defer { previous = sample }
        guard let previous else { return .initial }
        let wall = sample.wallMilliseconds.subtractingReportingOverflow(previous.wallMilliseconds)
        let monotonic = sample.monotonicMilliseconds.subtractingReportingOverflow(previous.monotonicMilliseconds)
        guard !wall.overflow, !monotonic.overflow, wall.partialValue >= 0,
              monotonic.partialValue >= 0 else { return .clockAnomaly }
        // Both deltas are nonnegative, so subtraction cannot overflow.
        guard abs(wall.partialValue - monotonic.partialValue) <= 1_000 else { return .clockAnomaly }
        return monotonic.partialValue > 10_000 ? .collectionGap : .continuous
    }
}
