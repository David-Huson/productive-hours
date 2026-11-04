import Foundation

/// Only the latest observation can attribute a hostname. Failed reads replace successful ones.
public struct BrowserObservationState: Sendable {
    public private(set) var latest: BrowserObservation?

    public init() {}

    public mutating func record(_ observation: BrowserObservation) {
        latest = observation
    }

    public mutating func reset() {
        latest = nil
    }

    public func hostname(for app: String, at now: Date) -> String? {
        guard let latest, latest.app == app, let host = latest.host, !host.isEmpty else { return nil }
        let age = now.timeIntervalSince(latest.observedAt)
        guard age >= 0, age <= 10 else { return nil }
        return host
    }
}
