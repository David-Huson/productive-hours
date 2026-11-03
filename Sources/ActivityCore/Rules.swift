import Foundation

public struct ClassificationRule: Codable, Identifiable, Equatable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable { case app, domain, subdomains, exactHost }
    public var id: String = UUID().uuidString
    public var kind: Kind
    public var pattern: String
    public var productivity: ProductivityClass
    public var priority: Int = 0
    public var enabled = true
    public var version = 1
    /// Optional friendly label; matching still uses `pattern` only.
    public var displayName: String?
    public var label: String {
        let trimmed = displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? pattern : trimmed
    }
    public init(kind: Kind, pattern: String, productivity: ProductivityClass, priority: Int = 0, displayName: String? = nil) {
        self.kind = kind; self.pattern = pattern; self.productivity = productivity; self.priority = priority
        self.displayName = displayName
    }
}

public enum RuleEvaluator {
    public static func hostname(_ value: String) -> String? {
        let host = value.lowercased().trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard host.count <= 253, !host.isEmpty, host.split(separator: ".", omittingEmptySubsequences: false).allSatisfy({ label in
            !label.isEmpty && label.count <= 63 && label.first != "-" && label.last != "-" && label.utf8.allSatisfy { (97...122).contains($0) || (48...57).contains($0) || $0 == 45 }
        }) else { return nil }
        return host
    }
    public static func resolve(app: String, host: String?, rules: [ClassificationRule]) -> Source {
        let safeHost = host.flatMap(hostname)
        let matches = rules.filter { rule in
            guard rule.enabled else { return false }
            if rule.kind == .app { return rule.pattern == app }
            guard let safeHost, let pattern = hostname(rule.pattern) else { return false }
            switch rule.kind {
            case .exactHost: return safeHost == pattern
            case .subdomains: return safeHost.hasSuffix("." + pattern)
            case .domain: return safeHost == pattern || safeHost.hasSuffix("." + pattern)
            case .app: return false
            }
        }.sorted { lhs, rhs in
            let rank: [ClassificationRule.Kind: Int] = [.app: 0, .domain: 1, .subdomains: 2, .exactHost: 3]
            if rank[lhs.kind] != rank[rhs.kind] { return rank[lhs.kind]! > rank[rhs.kind]! }
            if (lhs.kind == .subdomains || lhs.kind == .domain) && lhs.pattern.count != rhs.pattern.count { return lhs.pattern.count > rhs.pattern.count }
            if lhs.priority != rhs.priority { return lhs.priority > rhs.priority }
            return lhs.id < rhs.id
        }
        let rule = matches.first
        return Source(app: app, host: safeHost, productivity: rule?.productivity ?? .undefined,
                      ruleID: rule?.id, ruleVersion: rule?.version ?? 0)
    }
}

public struct AppSettings: Codable, Equatable, Sendable {
    public var timezone = TimeZone.current.identifier
    public var weekStart = 2
    public var minimumHours = 35.0
    public var maximumHours = 40.0
    public var workdays: Set<Int> = [2,3,4,5,6]
    public var startHour = 9
    public var endHour = 17
    public var activeMinutes = 2
    public var passiveMinutes = 5
    public var retentionDays = 90
    public var notifications = false
    public var idleWarningAfterSeconds: Int?
    /// Seconds before the active→passive boundary; nil inherits `idleWarningAfterSeconds` then 90.
    public var warnBeforePassiveSeconds: Int?
    /// Seconds before the passive→inactive boundary; 0 disables.
    public var warnBeforeInactiveSeconds: Int?
    public var warnWhenEnteringPassive = false
    public var warnWhenEnteringInactive = false
    public var effectiveIdleWarningSeconds: Int { effectiveWarnBeforePassiveSeconds }
    public var effectiveWarnBeforePassiveSeconds: Int {
        let raw = warnBeforePassiveSeconds ?? idleWarningAfterSeconds ?? 90
        let cap = max(0, activeMinutes * 60 - 5)
        return min(max(0, raw), cap)
    }
    public var effectiveWarnBeforeInactiveSeconds: Int {
        let raw = warnBeforeInactiveSeconds ?? 0
        let cap = max(0, passiveMinutes * 60 - 5)
        return min(max(0, raw), cap)
    }
    public var quietStart = 18
    public var quietEnd = 9
    public var browserEnabled = false
    public var monitoringEnabled = false
    public var hasConsented = false
    public init() {}
    public var valid: Bool {
        TimeZone(identifier: timezone) != nil && (1...7).contains(weekStart) && minimumHours > 0 && maximumHours >= minimumHours && maximumHours <= 168 && startHour >= 0 && endHour <= 24 && startHour < endHour && activeMinutes > 0 && activeMinutes <= 60 && passiveMinutes >= 0 && passiveMinutes <= 120 && retentionDays >= 1 && retentionDays <= 3650 && (0...23).contains(quietStart) && (0...23).contains(quietEnd) && workdays.isSubset(of: Set(1...7))
    }
    public var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: timezone) ?? .gmt
        c.firstWeekday = weekStart; c.minimumDaysInFirstWeek = 1
        return c
    }
}
