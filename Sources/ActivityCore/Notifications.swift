import Foundation

/// One warning per idle episode, before the active-to-passive transition.
public struct IdleWarningState: Sendable {
    private var warned = false
    public init() {}
    public mutating func evaluate(idleMS: Int64?, warningSeconds: Int, activeMinutes: Int, eligible: Bool) -> Bool {
        guard let idleMS, warningSeconds > 0 else { warned = false; return false }
        let threshold = Int64(warningSeconds) * 1000
        if idleMS < threshold { warned = false; return false }
        guard eligible, !warned, idleMS < Int64(activeMinutes) * 60_000 else { return false }
        warned = true
        return true
    }
}

public enum NotificationPolicy {
    public static func canDeliver(now: Date, settings: AppSettings, lastSent: Date?, snoozedUntil: Date?) -> Bool {
        guard settings.notifications, snoozedUntil.map({ $0 <= now }) ?? true else { return false }
        let calendar = settings.calendar
        let hour = calendar.component(.hour, from: now)
        let quiet = settings.quietStart > settings.quietEnd
            ? hour >= settings.quietStart || hour < settings.quietEnd
            : hour >= settings.quietStart && hour < settings.quietEnd
        if quiet { return false }
        if let lastSent, calendar.isDate(lastSent, inSameDayAs: now) { return false }
        return true
    }
}

public struct ForecastAlertState: Codable, Sendable {
    public private(set) var direction: String?
    public private(set) var since: Date?
    public init() {}
    public mutating func evaluate(projection: Double?, minimum: Double, maximum: Double, now: Date) -> String? {
        guard let projection, projection < minimum || projection > maximum else { direction = nil; since = nil; return nil }
        let next = projection < minimum ? "behind_weekly_pace" : "projected_over_maximum"
        if direction != next { direction = next; since = now }
        guard let since, now.timeIntervalSince(since) >= 1800 else { return nil }
        return next
    }
}
