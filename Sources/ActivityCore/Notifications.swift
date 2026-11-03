import Foundation

/// Fires once on each eligible active→passive or active/passive→inactive edge.
public struct ActivityTransitionNotifier: Sendable {
    private var previous: ActivityState = .unknown
    public enum Transition: String, Sendable { case enteredPassive, enteredInactive }
    public init() {}
    public mutating func evaluate(current: ActivityState, eligible: Bool) -> Transition? {
        defer { previous = current }
        guard eligible else { return nil }
        if current == .passive && previous == .active { return .enteredPassive }
        if current == .inactive && (previous == .active || previous == .passive) { return .enteredInactive }
        return nil
    }
}

/// One advance warning per idle episode for each mode boundary.
public struct AdvanceModeWarningState: Sendable {
    private var warnedBeforePassive = false
    private var warnedBeforeInactive = false
    public struct Result: Sendable, Equatable {
        public var beforePassive: Bool
        public var beforeInactive: Bool
        public init(beforePassive: Bool = false, beforeInactive: Bool = false) {
            self.beforePassive = beforePassive
            self.beforeInactive = beforeInactive
        }
    }
    public init() {}
    public mutating func evaluate(
        idleMS: Int64?,
        activeMS: Int64,
        passiveMS: Int64,
        warnBeforePassiveSeconds: Int,
        warnBeforeInactiveSeconds: Int,
        passiveEligible: Bool,
        inactiveEligible: Bool
    ) -> Result {
        guard let idleMS else { warnedBeforePassive = false; warnedBeforeInactive = false; return Result() }
        var result = Result()
        if warnBeforePassiveSeconds > 0 {
            let lead = Int64(warnBeforePassiveSeconds) * 1000
            let boundary = activeMS
            if idleMS < max(0, boundary - lead) { warnedBeforePassive = false }
            else if passiveEligible, !warnedBeforePassive, idleMS >= boundary - lead, idleMS < boundary {
                warnedBeforePassive = true
                result.beforePassive = true
            }
        } else { warnedBeforePassive = false }
        if warnBeforeInactiveSeconds > 0 {
            let lead = Int64(warnBeforeInactiveSeconds) * 1000
            let boundary = activeMS + passiveMS
            if idleMS < max(0, boundary - lead) { warnedBeforeInactive = false }
            else if inactiveEligible, !warnedBeforeInactive, idleMS >= boundary - lead, idleMS < boundary {
                warnedBeforeInactive = true
                result.beforeInactive = true
            }
        } else { warnedBeforeInactive = false }
        return result
    }
}

public typealias IdleWarningState = AdvanceModeWarningState

public enum NotificationPolicy {
    public static func canDeliver(now: Date, settings: AppSettings, lastSent: Date?, snoozedUntil: Date?) -> Bool {
        guard settings.notifications, snoozedUntil.map({ $0 <= now }) ?? true else { return false }
        if isQuietHour(now: now, settings: settings) { return false }
        if let lastSent, settings.calendar.isDate(lastSent, inSameDayAs: now) { return false }
        return true
    }
    /// Activity and idle-boundary alerts ignore quiet hours so late work still gets passive/inactive warnings.
    public static func canDeliverActivityAlert(now: Date, settings: AppSettings, snoozedUntil: Date?) -> Bool {
        guard settings.notifications, snoozedUntil.map({ $0 <= now }) ?? true else { return false }
        return true
    }
    public static func isQuietHour(now: Date, settings: AppSettings) -> Bool {
        let hour = settings.calendar.component(.hour, from: now)
        return settings.quietStart > settings.quietEnd
            ? hour >= settings.quietStart || hour < settings.quietEnd
            : hour >= settings.quietStart && hour < settings.quietEnd
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
