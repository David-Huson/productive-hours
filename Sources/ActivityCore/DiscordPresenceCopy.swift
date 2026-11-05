import Foundation

public struct DiscordPresenceFormatted: Equatable, Sendable {
    public var details: String
    public var state: String
    public var largeImageText: String
    public var smallImageKey: String
    public var startTimestamp: Int64?
}

public enum DiscordPresenceCopy {
    public static func format(
        indicator: MenuBarActivityIndicator,
        todayProductive: Double,
        week: WeeklyMetrics,
        calendar: Calendar,
        showDaily: Bool,
        showWeekly: Bool,
        showBreakdown: Bool,
        trackingStartedAt: Date?
    ) -> DiscordPresenceFormatted? {
        guard let status = statusLabel(for: indicator) else { return nil }
        let emoji = statusEmoji(for: indicator)
        let details = clip("Worktempo: \(status) \(emoji)")
        var stateLine: [String] = []
        if showDaily { stateLine.append("\(Metrics.duration(todayProductive)) today") }
        if showWeekly { stateLine.append("\(Metrics.duration(week.productive)) this week") }
        let state = clip(stateLine.joined(separator: "  ·  "))
        let largeImageText: String
        if showBreakdown {
            let breakdown = weeklyBreakdown(week: week, calendar: calendar)
            largeImageText = clip("This week — \(breakdown)")
        } else {
            largeImageText = "Estimated productive digital time"
        }
        let startTimestamp = trackingStartedAt.map { Int64($0.timeIntervalSince1970) }
        return DiscordPresenceFormatted(
            details: details,
            state: state,
            largeImageText: largeImageText,
            smallImageKey: smallImageKey(for: indicator),
            startTimestamp: startTimestamp)
    }

    private static func statusLabel(for indicator: MenuBarActivityIndicator) -> String? {
        switch indicator {
        case .active: "Active"
        case .passive: "Passive"
        case .inactive: "Inactive"
        case .unproductive: "Unproductive"
        case .hidden: nil
        }
    }

    private static func statusEmoji(for indicator: MenuBarActivityIndicator) -> String {
        switch indicator {
        case .active: "🟢"
        case .passive: "🔵"
        case .inactive: "🟡"
        case .unproductive: "🔴"
        case .hidden: ""
        }
    }

    private static func smallImageKey(for indicator: MenuBarActivityIndicator) -> String {
        switch indicator {
        case .active: "status_active"
        case .passive: "status_passive"
        case .inactive: "status_inactive"
        case .unproductive: "status_unproductive"
        case .hidden: ""
        }
    }

    private static func weeklyBreakdown(week: WeeklyMetrics, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate("EEE")
        return week.days.map { day in
            "\(formatter.string(from: day.date)) \(Metrics.duration(day.productive))"
        }.joined(separator: " · ")
    }

    private static func clip(_ value: String) -> String {
        String(value.prefix(128))
    }
}
