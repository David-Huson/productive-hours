import Foundation

public struct Source: Codable, Equatable, Sendable {
    public var app: String
    public var host: String?
    public var productivity: ProductivityClass
    public var ruleID: String?
    public var ruleVersion: Int
    public var privateBrowsing: Bool
    public init(app: String = "", host: String? = nil, productivity: ProductivityClass = .undefined, ruleID: String? = nil, ruleVersion: Int = 0, privateBrowsing: Bool = false) {
        self.app = app; self.host = host; self.productivity = productivity; self.ruleID = ruleID; self.ruleVersion = ruleVersion; self.privateBrowsing = privateBrowsing
    }
}

public struct Interval: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var start: Int64
    public var end: Int64
    public var source: Source
    public var activity: ActivityState
    public var reason: String
    public var seconds: Double { Double(end - start) / 1000 }
    public var productive: Bool { !source.privateBrowsing && ActivityClassification(productivity: source.productivity, activity: activity).creditsProductiveTime }
    public init(id: String = UUID().uuidString, start: Int64, end: Int64, source: Source, activity: ActivityState, reason: String = "observed") {
        self.id = id; self.start = start; self.end = end; self.source = source; self.activity = activity; self.reason = reason
    }
}

public enum TrackingEvent: Sendable {
    case input, observedIdle(Int64), foreground(Source), barrier(String, Bool), pause(Bool), failure, recovered, tick
    case call(Source?)
}

public struct CallEvidence: Codable, Sendable {
    public var source: Source
    public var expiresAt: Int64
}

/// No platform, database or UI state. Caller commits the proposed state and intervals together.
public struct TrackingEngine: Codable, Sendable {
    public private(set) var boundary: Int64
    public private(set) var lastInput: Int64?
    public private(set) var source = Source()
    public private(set) var barriers: Set<String> = []
    public private(set) var paused = true
    public private(set) var healthy = false
    public private(set) var call: CallEvidence?
    public var activeMS: Int64 = 120_000
    public var passiveMS: Int64 = 300_000
    public init(start: Int64) { boundary = start }

    public var state: ActivityState { state(at: boundary) }
    public var isCallCrediting: Bool {
        callSource(at: boundary) != nil && (state == .active || state == .passive)
    }
    private func callSource(at time: Int64) -> Source? {
        guard !source.privateBrowsing, source.productivity != .ignored,
              let call, time < call.expiresAt else { return nil }
        return call.source
    }
    private func state(at time: Int64) -> ActivityState {
        if !barriers.isEmpty { return .inactive }
        if paused || !healthy { return .unknown }
        guard let lastInput else { return .unknown }
        let idle = max(0, time - lastInput)
        if idle < activeMS { return .active }
        if callSource(at: time) != nil { return .passive }
        if idle < activeMS + passiveMS { return .passive }
        return .inactive
    }

    public mutating func apply(_ event: TrackingEvent, at time: Int64) -> [Interval] {
        guard time >= boundary else { return [] }
        var cuts = [boundary, time]
        if let expiry = call?.expiresAt, expiry > boundary && expiry < time { cuts.append(expiry) }
        if let lastInput {
            for offset in [activeMS, activeMS + passiveMS] {
                let value = lastInput.addingReportingOverflow(offset)
                if !value.overflow && value.partialValue > boundary && value.partialValue < time { cuts.append(value.partialValue) }
            }
        }
        cuts = Array(Set(cuts)).sorted()
        let intervals = zip(cuts, cuts.dropFirst()).map { start, end in
            let callSource = callSource(at: start)
            return Interval(start: start, end: end, source: callSource ?? source, activity: state(at: start),
                     reason: paused ? "paused" : (!healthy ? "collector_gap" : (barriers.sorted().first ?? (callSource == nil ? "observed" : "call_audio"))))
        }
        boundary = time
        switch event {
        case .input: lastInput = time
        case .observedIdle(let age): lastInput = time - max(0, age)
        case .foreground(let next): source = next
        case .barrier(let name, let entering):
            call = nil
            if entering { barriers.insert(name) } else { barriers.remove(name); lastInput = nil; healthy = false }
        case .pause(let value): paused = value; lastInput = nil; healthy = false; call = nil
        case .failure: healthy = false; lastInput = nil; call = nil
        case .call(let next):
            let expiry = time.addingReportingOverflow(10_000)
            call = next.flatMap { source in
                guard !expiry.overflow, source.productivity == .productive, !source.privateBrowsing else { return nil }
                return CallEvidence(source: source, expiresAt: expiry.partialValue)
            }
        case .recovered: healthy = true
        case .tick: break
        }
        return intervals
    }

    /// Any uncommitted downtime is unknown. Never extend the previous productive source.
    public mutating func recover(at time: Int64) -> [Interval] {
        healthy = false; lastInput = nil; barriers.removeAll(); call = nil
        return apply(.tick, at: time)
    }
}

public extension Date {
    var epochMS: Int64 { Int64((timeIntervalSince1970 * 1000).rounded(.down)) }
    init(epochMS: Int64) { self.init(timeIntervalSince1970: Double(epochMS) / 1000) }
}
