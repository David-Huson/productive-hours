import Foundation

public struct DayTotal: Codable, Identifiable, Sendable {
    public var id: String
    public var date: Date
    public var active = 0.0
    public var passive = 0.0
    public var unproductive = 0.0
    public var undefined = 0.0
    public var ignored = 0.0
    public var inactive = 0.0
    public var unknown = 0.0
    public var scheduledEligible = 0.0
    public var scheduledProductive = 0.0
    public var scheduledUnknown = 0.0
    public var productive: Double { active + passive }
    public var observed: Double { productive + unproductive + undefined + ignored + inactive }
}

public struct WeeklyMetrics: Sendable {
    public var start: Date
    public var end: Date
    public var days: [DayTotal]
    public var productive: Double { days.reduce(0) { $0 + $1.productive } }
    public var unknown: Double { days.reduce(0) { $0 + $1.unknown } }
    public var minimum: Double
    public var maximum: Double
    public var remainingCapacity: Double
    public var projection: Double?
    public var projectionLow: Double?
    public var projectionHigh: Double?
    public var usableDays: Int
    public var remaining: Double { max(0, minimum - productive) }
    public var headroom: Double { max(0, maximum - productive) }
    public var overage: Double { max(0, productive - maximum) }
    public var status: String {
        if remainingCapacity == 0 { return productive < minimum ? "Below target" : (productive > maximum ? "Above target" : "Target met") }
        if productive > maximum { return "Above target" }
        guard let projection else { return productive >= minimum ? "Minimum met" : "Calibrating" }
        return projection < minimum ? "Behind pace" : (projection > maximum ? "Above pace" : "On track")
    }
}

public enum Metrics {
    public static func dayLabel(_ date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter(); formatter.calendar = calendar; formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate("EEE MMM d yyyy")
        return formatter.string(from: date)
    }
    public static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let p = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", p.year!, p.month!, p.day!)
    }
    public static func schedule(on day: Date, settings: AppSettings) -> DateInterval? {
        let c = settings.calendar
        guard settings.workdays.contains(c.component(.weekday, from: day)) else { return nil }
        let midnight = c.startOfDay(for: day)
        guard let start = c.date(bySettingHour: settings.startHour, minute: 0, second: 0, of: midnight),
              let end = settings.endHour == 24 ? c.date(byAdding: .day, value: 1, to: midnight) : c.date(bySettingHour: settings.endHour, minute: 0, second: 0, of: midnight), end > start else { return nil }
        return DateInterval(start: start, end: end)
    }
    public static func aggregate(_ intervals: [Interval], settings: AppSettings) -> [DayTotal] {
        let c = settings.calendar
        var totals: [String: DayTotal] = [:]
        for interval in intervals where interval.end > interval.start {
            var cursor = Date(epochMS: interval.start)
            let finish = Date(epochMS: interval.end)
            while cursor < finish {
                let day = c.startOfDay(for: cursor)
                let next = c.date(byAdding: .day, value: 1, to: day)!
                // Explicitly split at DST transitions as well as local midnight.
                let dst = c.timeZone.nextDaylightSavingTimeTransition(after: cursor)
                let end = min(finish, next, dst.map { $0 > cursor ? $0 : next } ?? next)
                let seconds = end.timeIntervalSince(cursor)
                let key = dayKey(day, calendar: c)
                var total = totals[key] ?? DayTotal(id: key, date: day)
                let productivity: ProductivityClass = interval.source.privateBrowsing ? .ignored : interval.source.productivity
                switch interval.activity {
                case .unknown: total.unknown += seconds
                case .inactive: total.inactive += seconds
                case .active, .passive:
                    switch productivity {
                    case .productive:
                        if interval.activity == .active { total.active += seconds } else { total.passive += seconds }
                    case .unproductive: total.unproductive += seconds
                    case .undefined: total.undefined += seconds
                    case .ignored: total.ignored += seconds
                    }
                }
                if let schedule = schedule(on: day, settings: settings) {
                    let eligible = max(0, min(end, schedule.end).timeIntervalSince(max(cursor, schedule.start)))
                    if interval.activity == .unknown { total.scheduledUnknown += eligible }
                    else if productivity != .ignored || interval.activity == .inactive {
                        total.scheduledEligible += eligible
                        if interval.productive { total.scheduledProductive += eligible }
                    }
                }
                totals[key] = total; cursor = end
            }
        }
        return totals.values.sorted { $0.date < $1.date }
    }
    public static func week(containing date: Date, now: Date, totals: [DayTotal], settings: AppSettings) -> WeeklyMetrics {
        let c = settings.calendar
        let bounds = c.dateInterval(of: .weekOfYear, for: date)!
        var days: [DayTotal] = []
        var capacity = 0.0
        for offset in 0..<7 {
            let day = c.date(byAdding: .day, value: offset, to: bounds.start)!
            let key = dayKey(day, calendar: c)
            days.append(totals.first { $0.id == key } ?? DayTotal(id: key, date: day))
            if let schedule = schedule(on: day, settings: settings) {
                capacity += max(0, schedule.end.timeIntervalSince(max(now, schedule.start)))
            }
        }
        let lookback = c.date(byAdding: .day, value: -28, to: now)!
        let usable = totals.filter { $0.date >= lookback && $0.date <= now && $0.scheduledEligible >= 1800 && $0.scheduledUnknown / max(1, $0.scheduledEligible + $0.scheduledUnknown) <= 0.1 }
        var denominator = 0.0, numerator = 0.0
        var yields: [Double] = []
        for day in usable {
            let weight = pow(0.9, max(0, now.timeIntervalSince(day.date) / 86400))
            denominator += day.scheduledEligible * weight
            numerator += day.scheduledProductive * weight
            yields.append(day.scheduledProductive / day.scheduledEligible)
        }
        let productive = days.reduce(0) { $0 + $1.productive }
        let unknown = days.reduce(0) { $0 + $1.scheduledUnknown }
        let eligible = days.reduce(0) { $0 + $1.scheduledEligible }
        let confident = usable.count >= 3 && unknown / max(1, unknown + eligible) <= 0.1
        let yield = min(1, max(0, numerator / max(1, denominator)))
        return WeeklyMetrics(start: bounds.start, end: bounds.end, days: days,
            minimum: settings.minimumHours * 3600, maximum: settings.maximumHours * 3600,
            remainingCapacity: capacity, projection: confident ? productive + capacity * yield : nil,
            projectionLow: confident ? productive + capacity * (yields.min() ?? yield) : nil,
            projectionHigh: confident ? productive + capacity * (yields.max() ?? yield) : nil, usableDays: usable.count)
    }
    public static func duration(_ seconds: Double) -> String {
        let minutes = Int(max(0, seconds) / 60)
        return "\(minutes / 60)h \(minutes % 60)m"
    }
}
