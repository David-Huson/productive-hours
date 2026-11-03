import Foundation
import AppKit
import Combine
import UserNotifications
import ServiceManagement
import ActivityCore
import PlatformCollectors
import Persistence
import DiscordPresence

@MainActor
final class TrackingService: ObservableObject {
    @Published var settings = AppSettings()
    @Published var editedSettings = AppSettings()
    @Published var rules: [ClassificationRule] = []
    @Published var ruleRevisions: [RuleRevision] = []
    @Published var typeSnoozes: [String: Date] = [:]
    @Published var intervals: [Interval] = []
    @Published var totals: [DayTotal] = []
    @Published var references: [ReferenceTotal] = []
    @Published var manual: [ManualWork] = []
    @Published var currentState: ActivityState = .unknown
    @Published private(set) var menuBarActivityIndicator: MenuBarActivityIndicator = .hidden
    @Published var currentApp = ""
    @Published var status = "Paused"
    @Published var stablePace = "Loading"
    private var paceCandidate: (String, Date)?
    @Published var browserStatus = "Browser tracking disabled"
    @Published var callStatus = "No call observed"
    @Published var error: String?
    @Published var message: String?
    @Published var lastUpdated = Date()
    @Published var running = false
    @Published var weekOffset = 0
    @Published var meetingEnd: Date?
    @Published var ruleKind: ClassificationRule.Kind = .app
    @Published var rulePattern = ""
    @Published var ruleDisplayName = ""
    @Published var ruleClass: ProductivityClass = .productive
    @Published var rulePriority = 0
    @Published var preview: String?
    @Published var referenceDate = Date()
    @Published var referenceHours = 0.0
    @Published var referenceTimezone = TimeZone.current.identifier
    @Published var referenceMetric = "Productive"
    @Published var snoozedUntil: Date?
    @Published var confirmDelete = false
    @Published var loginEnabled = false
    private var store: Store?
    private var engine = TrackingEngine(start: Date().epochMS)
    private var pending: [Interval] = []
    private let collector = PlatformCollector()
    private let discordPresence = DiscordPresenceClient()
    private var discordTrackingStartedAt: Date?
    private let browser = BrowserObserver()
    private var browserTask: Task<Void, Never>?
    private var browserObservation: BrowserObservation?
    private var lastBrowserRead = Date.distantPast
    private var lastCommit = Date.distantPast
    private var lastRetention = Date.distantPast
    private var accepting = false
    private var refreshTimer: Timer?
    private var meetingStart: Date?
    private var forecastAlert = ForecastAlertState()
    private var advanceModeWarning = AdvanceModeWarningState()
    private var activityTransition = ActivityTransitionNotifier()
    private var archived: [ArchivedDay] = []
    private var notificationDates: [String: Date] = [:]
    private var pendingRules: [ClassificationRule]?
    private var trace = DiagnosticTrace(fileURL: FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Application Support/ProductiveHours/Diagnostics/phase-0.json"))
    static let directory = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Application Support/ProductiveHours")

    init() {
        AppDelegate.service = self
        do {
            let storage = try Store(url: Self.directory.appending(path: "activity.sqlite"))
            store = storage
            settings = try storage.load("settings", as: AppSettings.self) ?? AppSettings()
            guard settings.valid else { throw StoreError.invalidData }
            editedSettings = settings
            rules = try storage.load("rules", as: [ClassificationRule].self) ?? []
            notificationDates = try storage.load("notificationDates", as: [String: Date].self) ?? [:]
            typeSnoozes = try storage.load("typeSnoozes", as: [String: Date].self) ?? [:]
            snoozedUntil = try storage.load("snoozedUntil", as: Date.self)
            forecastAlert = try storage.load("forecastAlert", as: ForecastAlertState.self) ?? ForecastAlertState()
            if let checkpoint = try storage.load("checkpoint", as: TrackingEngine.self) {
                engine = checkpoint
                pending += engine.recover(at: Date().epochMS)
                flush()
            }
            if let meeting = try storage.load("meetingCheckpoint", as: MeetingCheckpoint.self) {
                if meeting.lastConfirmed > meeting.start { try storage.addManual(ManualWork(start: meeting.start, end: meeting.lastConfirmed, kind: "user_declared_meeting_recovered")) }
                try storage.remove("meetingCheckpoint")
            }
            refresh()
            loginEnabled = SMAppService.mainApp.status == .enabled
            collector.onObservation = { [weak self] observation in self?.observe(observation) }
            refreshMenuBarActivityIndicator()
            applyDiscordConfiguration()
            syncNotificationAuthorization()
            if settings.monitoringEnabled { start() }
            refreshTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.periodic() }
            }
            if let refreshTimer { RunLoop.main.add(refreshTimer, forMode: .common) }
        } catch { self.error = error.localizedDescription; status = "Storage unavailable" }
    }

    var week: WeeklyMetrics {
        let now = Date()
        let date = settings.calendar.date(byAdding: .weekOfYear, value: weekOffset, to: now)!
        return Metrics.week(containing: date, now: now, totals: totals, settings: settings)
    }
    var liveWeek: WeeklyMetrics { Metrics.week(containing: Date(), now: Date(), totals: totals, settings: settings) }
    var menuTitle: String {
        if error != nil { return "Data gap" }
        if !running { return "Paused" }
        if !engine.isCallCrediting && BrowserObserver.browsers.contains(currentApp) && browserObservation?.host == nil { return "Limited coverage" }
        if currentState == .unknown { return "Data gap" }
        return stablePace
    }
    var menuSymbol: String {
        if !running { return "pause.circle" }
        switch menuTitle {
        case "On track", "Target met", "Minimum met": return "checkmark.circle"
        case "Behind pace": return "arrow.down.right.circle"
        case "Above pace", "Above target": return "arrow.up.right.circle"
        case "Loading", "Schedule not started": return "clock"
        default: return "exclamationmark.circle"
        }
    }
    var isCallCrediting: Bool { running && error == nil && engine.isCallCrediting }
    var menuBarIcon: NSImage { MenuBarIconComposer.make(indicator: menuBarActivityIndicator) }
    private func refreshMenuBarActivityIndicator() {
        menuBarActivityIndicator = MenuBarActivityIndicatorPolicy.resolve(
            running: running,
            hasError: error != nil,
            productivity: engine.source.productivity,
            activity: currentState
        )
        refreshDiscordPresence()
    }
    private func applyDiscordConfiguration() {
        discordPresence.configure(
            enabled: settings.discordRichPresenceEnabled && settings.discordApplicationIdValid,
            applicationId: settings.discordApplicationId)
    }
    private func refreshDiscordPresence() {
        applyDiscordConfiguration()
        let today = totals.first { settings.calendar.isDateInToday($0.date) }?.productive ?? 0
        let formatted = DiscordPresenceCopy.format(
            indicator: menuBarActivityIndicator,
            todayProductive: today,
            week: liveWeek,
            calendar: settings.calendar,
            showDaily: settings.discordShowDailyTotal,
            showWeekly: settings.discordShowWeeklyTotal,
            showBreakdown: settings.discordShowWeeklyBreakdown,
            trackingStartedAt: discordTrackingStartedAt)
        discordPresence.update(presence: formatted, tracking: running && error == nil)
    }
    var advice: String {
        if let error { return error }
        if !running { return "Tracking is paused. Paused time is a gap in the estimate." }
        if menuTitle == "Limited coverage" { return "Browser domain unavailable. Review browser access or set an explicit app rule." }
        switch stablePace {
        case "Behind pace": return "Logged productive time is below your target pace for the elapsed work schedule."
        case "Above pace": return "Logged productive time is ahead of your target pace for the elapsed work schedule."
        case "Minimum met", "Target met": return "You have reached your weekly minimum target."
        case "Above target": return "Logged productive time is above your weekly maximum."
        case "Below target": return "The work schedule has ended below your minimum target."
        case "Set work schedule": return "Select workdays in Settings to calculate your target pace."
        case "Schedule not started": return "Your scheduled workweek has not started yet."
        default: return "Logged productive time is on pace for your target and elapsed work schedule."
        }
    }
    private func append(_ values: [Interval]) {
        for value in values where value.end > value.start {
            if let previous = pending.last, previous.end == value.start, previous.source == value.source, previous.activity == value.activity, previous.reason == value.reason {
                pending[pending.count - 1].end = value.end
            } else { pending.append(value) }
        }
    }
    private func apply(_ event: TrackingEvent, at time: Int64) { append(engine.apply(event, at: time)) }

    func retryStorage() {
        accepting = false; collector.stop(); running = false
        do {
            store = nil
            let storage = try Store(url: Self.directory.appending(path: "activity.sqlite"))
            store = storage
            engine = try storage.load("checkpoint", as: TrackingEngine.self) ?? TrackingEngine(start: Date().epochMS)
            guard Date().epochMS >= engine.boundary else { throw CSVError.invalid("Clock is earlier than the last durable interval. Resume after the clock catches up or correct the system clock.") }
            pending = engine.recover(at: Date().epochMS)
            error = nil; flush(); status = "Paused"
        } catch { self.error = error.localizedDescription }
    }
    func start() {
        guard store != nil, error == nil, !running else { return }
        let now = Date().epochMS
        guard now >= engine.boundary else { error = "Clock moved backward. Wait until the last recorded timestamp before resuming."; return }
        engine.activeMS = Int64(settings.activeMinutes) * 60_000
        engine.passiveMS = Int64(settings.passiveMinutes) * 60_000
        apply(.pause(false), at: now)
        browserObservation = nil; lastBrowserRead = .distantPast
        running = true; accepting = true; settings.monitoringEnabled = true; settings.hasConsented = true
        do { try store?.save("settings", value: settings) } catch { fail(error); return }
        activityTransition = ActivityTransitionNotifier()
        advanceModeWarning = AdvanceModeWarningState()
        discordTrackingStartedAt = Date()
        refreshMenuBarActivityIndicator()
        collector.start(); flush()
    }
    func pause() {
        accepting = false; collector.stop(); browserTask?.cancel(); browserTask = nil; browserObservation = nil
        apply(.pause(true), at: max(engine.boundary, Date().epochMS))
        running = false; status = "Paused"; settings.monitoringEnabled = false
        callStatus = "Call observation paused"
        discordTrackingStartedAt = nil
        refreshMenuBarActivityIndicator()
        discordPresence.shutdown()
        do { try store?.save("settings", value: settings) } catch { fail(error) }
        endMeeting(); flush()
    }
    func shutdown() { guard settings.hasConsented || meetingStart != nil else { return }; accepting = false; collector.stop(); apply(.failure, at: max(engine.boundary, Date().epochMS)); endMeeting(); flush() }
    private func fail(_ failure: Error) {
        error = failure.localizedDescription; accepting = false; running = false; collector.stop(); status = "Data gap"
        refreshMenuBarActivityIndicator()
    }
    private func observe(_ observation: DiagnosticObservation) {
        guard accepting else { return }
        let now = observation.timestamp.epochMS
        guard now >= engine.boundary else {
            apply(.failure, at: engine.boundary); flush()
            error = "Clock moved backward. Tracking stopped to prevent overlapping time."; accepting = false; running = false; collector.stop(); return
        }
        do { try trace.record(observation) } catch { message = "Diagnostic log unavailable; accounting storage remains active." }
        if observation.health == .clockAnomaly || observation.health == .collectionGap {
            apply(.failure, at: engine.boundary)
        }
        if let age = observation.idleMilliseconds, age >= 0 {
            let inputAt = now - age
            if inputAt > engine.boundary && (engine.lastInput == nil || inputAt > engine.lastInput! + 500) { apply(.input, at: inputAt) }
        }
        apply(.tick, at: now)
        let barriers: [String: (String, Bool)] = ["sleep": ("sleep", true), "wake": ("sleep", false), "display_sleep": ("display", true), "display_wake": ("display", false), "session_inactive": ("session", true), "session_active": ("session", false)]
        if let (name, entering) = barriers[observation.event] { apply(.barrier(name, entering), at: now) }
        let app = observation.bundleID ?? ""
        if app != currentApp { browserObservation = nil }
        currentApp = app
        let freshHost = browserObservation.flatMap { value in value.app == app && observation.timestamp.timeIntervalSince(value.observedAt) <= 10 ? value.host : nil }
        var source = RuleEvaluator.resolve(app: app, host: freshHost, rules: rules)
        if browserObservation?.status == "Private browsing excluded" && browserObservation?.app == app { source.productivity = .ignored; source.ruleID = nil; source.privateBrowsing = true }
        apply(.foreground(source), at: now)
        if let idle = observation.idleMilliseconds, !app.isEmpty {
            apply(.observedIdle(idle), at: now)
            apply(.recovered, at: now)
        } else { apply(.failure, at: now) }
        do {
            let callSource = CallAudioProbe.productiveSource(try CallAudioProbe.sample(), rules: rules)
            apply(.call(callSource), at: now)
            callStatus = callSource.map { "\($0.app == "us.zoom.xos" ? "Zoom" : "Discord") audio active · counted once as productive while tracking is active and no exclusion applies" } ?? "No call audio active"
        } catch {
            apply(.call(nil), at: now)
            callStatus = "Call observation unavailable · using normal activity rules"
        }
        currentState = engine.state
        refreshMenuBarActivityIndicator()
        evaluateAdvanceModeWarnings(idleMS: observation.idleMilliseconds, now: observation.timestamp)
        evaluateActivityTransition(now: observation.timestamp)
        status = engine.state.rawValue.capitalized
        if observation.event != "sample" || Date().timeIntervalSince(lastCommit) >= 30 { flush() }
        if settings.browserEnabled && BrowserObserver.browsers.contains(app) && browserTask == nil && Date().timeIntervalSince(lastBrowserRead) >= 5 {
            lastBrowserRead = Date()
            browserTask = Task { [weak self, browser] in
                let value = await browser.observe(app: app)
                guard let self else { return }
                self.browserTask = nil
                guard !Task.isCancelled, self.running, self.settings.browserEnabled, self.currentApp == value.app else { return }
                self.browserObservation = value; self.browserStatus = value.status
                // Domain events are observations, never input. Reconcile foreground at event delivery.
                self.collector.sample(event: "domain_changed")
            }
        }
    }
    private func periodic() {
        if !running && error == nil && settings.hasConsented { apply(.tick, at: max(engine.boundary, Date().epochMS)); flush() }
        if let end = meetingEnd, Date() >= end { endMeeting() }
        if let start = meetingStart, let end = meetingEnd {
            do { try store?.save("meetingCheckpoint", value: MeetingCheckpoint(start: start, lastConfirmed: min(Date(), end))) }
            catch { message = "Meeting checkpoint could not be saved." }
        }
        evaluateNotifications()
    }
    private func flush() {
        guard let store else { return }
        do {
            try store.commit(pending, checkpoint: engine)
            pending.removeAll(); lastCommit = Date(); lastUpdated = Date()
            if Date().timeIntervalSince(lastRetention) >= 86400 { try store.retain(settings: settings, now: Date()); lastRetention = Date() }
            refresh()
        } catch { fail(error) }
    }
    private func refresh() {
        guard let store else { return }
        do {
            intervals = try store.intervals(); ruleRevisions = try store.ruleRevisions(); references = try store.references(); manual = try store.manualWork(); archived = try store.archives()
            var grouped = Dictionary(uniqueKeysWithValues: Metrics.aggregate(intervals, settings: settings).map { ($0.id, $0) })
            for archive in archived where archive.timezone == settings.timezone {
                var value = archive.total
                if archive.configuration.workdays != settings.workdays || archive.configuration.startHour != settings.startHour || archive.configuration.endHour != settings.endHour {
                    value.scheduledEligible = 0; value.scheduledProductive = 0; value.scheduledUnknown = 0
                }
                if var existing = grouped[value.id] {
                    existing.active += value.active; existing.passive += value.passive; existing.unproductive += value.unproductive
                    existing.undefined += value.undefined; existing.ignored += value.ignored; existing.inactive += value.inactive; existing.unknown += value.unknown
                    existing.scheduledEligible += value.scheduledEligible; existing.scheduledProductive += value.scheduledProductive; existing.scheduledUnknown += value.scheduledUnknown
                    grouped[value.id] = existing
                } else { grouped[value.id] = value }
            }
            totals = grouped.values.sorted { $0.date < $1.date }
            let next = liveWeek.status
            if next == stablePace { paceCandidate = nil }
            else if ["Set work schedule", "Schedule not started", "Minimum met", "Target met", "Above target", "Below target"].contains(next) || ["Loading", "Set work schedule", "Schedule not started"].contains(stablePace) {
                stablePace = next; paceCandidate = nil
            } else if paceCandidate?.0 != next { paceCandidate = (next, Date()) }
            else if let candidate = paceCandidate, Date().timeIntervalSince(candidate.1) >= 300 { stablePace = next; paceCandidate = nil }
        } catch { fail(error) }
    }
    var hasUnsavedSettings: Bool { editedSettings != settings }
    func discardSettingsEdits() { editedSettings = settings }
    func saveSettings() {
        guard editedSettings.valid else { message = "Check timezone, target range, schedule, thresholds and retention."; return }
        if editedSettings.discordRichPresenceEnabled && !editedSettings.discordApplicationIdValid {
            message = "Enter a numeric Discord Application ID from the Developer Portal, or turn off Discord Rich Presence."
            return
        }
        let wasRunning = running
        if wasRunning { pause() }
        settings = editedSettings; settings.monitoringEnabled = wasRunning
        browserStatus = settings.browserEnabled ? "Waiting for supported browser" : "Browser tracking disabled"
        do {
            try store?.save("settings", value: settings)
            error = nil
            applyDiscordConfiguration()
            refresh()
            if wasRunning { start() }
        }
        catch { fail(error) }
    }
    func activityLabel(app: String, host: String?) -> String {
        let resolved = RuleEvaluator.resolve(app: app, host: host, rules: rules)
        if let ruleID = resolved.ruleID, let rule = rules.first(where: { $0.id == ruleID }) { return rule.label }
        if let host, !host.isEmpty { return host }
        return app.isEmpty ? "Unknown source" : app
    }
    func normalizedRulePattern(kind: ClassificationRule.Kind, raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 253 else {
            message = "Enter an app bundle ID or hostname."
            return nil
        }
        if kind == .app {
            guard trimmed.contains("."), trimmed.utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 46 }) else {
                message = "Enter an exact app bundle ID, such as com.apple.Terminal."
                return nil
            }
            return trimmed
        }
        guard let normalized = RuleEvaluator.hostname(trimmed) else {
            message = "Enter a hostname only, without scheme, path or wildcard."
            return nil
        }
        return normalized
    }
    private func normalizedDisplayName(_ raw: String?) -> String? {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return nil }
        guard trimmed.count <= 80 else {
            message = "Display name must be 80 characters or fewer."
            return nil
        }
        return trimmed
    }
    func addRule() {
        guard let pattern = normalizedRulePattern(kind: ruleKind, raw: rulePattern) else { return }
        guard normalizedDisplayName(ruleDisplayName.isEmpty ? nil : ruleDisplayName) != nil
            || ruleDisplayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let displayName = normalizedDisplayName(ruleDisplayName.isEmpty ? nil : ruleDisplayName)
        var new = rules
        if let index = new.firstIndex(where: { $0.kind == ruleKind && $0.pattern == pattern }) {
            new[index].productivity = ruleClass
            new[index].priority = rulePriority
            new[index].enabled = true
            if let displayName { new[index].displayName = displayName }
            new[index].version += 1
        } else {
            new.append(ClassificationRule(kind: ruleKind, pattern: pattern, productivity: ruleClass, priority: rulePriority, displayName: displayName))
        }
        saveRules(new)
        rulePattern = ""
        ruleDisplayName = ""
    }
    func updateRule(_ updated: ClassificationRule) {
        guard rules.contains(where: { $0.id == updated.id }) else { return }
        guard let pattern = normalizedRulePattern(kind: updated.kind, raw: updated.pattern) else { return }
        guard normalizedDisplayName(updated.displayName) != nil
            || (updated.displayName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) else { return }
        let displayName = normalizedDisplayName(updated.displayName)
        if rules.contains(where: { $0.id != updated.id && $0.kind == updated.kind && $0.pattern == pattern }) {
            message = "Another rule already uses this type and pattern."
            return
        }
        var new = rules
        guard let index = new.firstIndex(where: { $0.id == updated.id }) else { return }
        var rule = new[index]
        let matchingChanged = rule.kind != updated.kind || rule.pattern != pattern
            || rule.productivity != updated.productivity || rule.priority != updated.priority || rule.enabled != updated.enabled
        rule.kind = updated.kind
        rule.pattern = pattern
        rule.displayName = displayName
        rule.productivity = updated.productivity
        rule.priority = updated.priority
        rule.enabled = updated.enabled
        if matchingChanged { rule.version += 1 }
        new[index] = rule
        saveRules(new)
    }
    func removeRule(_ id: String) { saveRules(rules.filter { $0.id != id }) }
    func saveRules(_ new: [ClassificationRule]) {
        apply(.tick, at: max(engine.boundary, Date().epochMS)); flush()
        do { try store?.saveRuleSet(new); rules = new; ruleRevisions = try store?.ruleRevisions() ?? []; if accepting { collector.sample(event: "rules_changed") }; message = "Rules saved for future activity. Use Preview to recalculate retained history." }
        catch { fail(error) }
    }
    func previewReclassification() {
        let before = intervals.filter(\.productive).reduce(0) { $0 + $1.seconds }
        let after = intervals.reduce(0.0) { sum, interval in
            if interval.source.privateBrowsing { return sum }
            if interval.reason == "call_audio" { return sum + (interval.productive ? interval.seconds : 0) }
            let source = RuleEvaluator.resolve(app: interval.source.app, host: interval.source.host, rules: rules)
            return sum + (ActivityClassification(productivity: source.productivity, activity: interval.activity).creditsProductiveTime ? interval.seconds : 0)
        }
        pendingRules = rules
        preview = "Retained productive time: \(Metrics.duration(before)) → \(Metrics.duration(after)). Archived summaries cannot be recalculated. This change can be undone."
    }
    func applyReclassification() {
        guard let selected = pendingRules else { return }
        do { try store?.reclassify(rules: selected, previousRules: rules, at: Date()); preview = nil; pendingRules = nil; refresh() }
        catch { fail(error) }
    }
    func undoReclassification() {
        do { if let previous = try store?.undoReclassification() { rules = previous; refresh(); message = "Last retained-history recalculation undone." } }
        catch { fail(error) }
    }
    func beginMeeting(minutes: Int) {
        endMeeting(); let start = Date()
        do {
            try store?.save("meetingCheckpoint", value: MeetingCheckpoint(start: start, lastConfirmed: start))
            meetingStart = start; meetingEnd = start.addingTimeInterval(Double(minutes * 60))
            message = "Work meeting started. User-declared time stays separate from the automatic estimate."
        } catch { fail(error) }
    }
    func endMeeting() {
        guard let start = meetingStart, let plannedEnd = meetingEnd else { return }
        let end = min(Date(), plannedEnd); meetingStart = nil; meetingEnd = nil
        do { if end > start { try store?.addManual(ManualWork(start: start, end: end)) }; try store?.remove("meetingCheckpoint"); refresh() } catch { fail(error) }
    }
    func saveReference() {
        guard referenceHours.isFinite, referenceHours >= 0, referenceHours <= 25, TimeZone(identifier: referenceTimezone) != nil, !referenceMetric.isEmpty else { message = "Enter valid reference hours, timezone and metric."; return }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: referenceTimezone)!
        let key = Metrics.dayKey(referenceDate, calendar: calendar)
        let previous = references.filter { $0.day == key && $0.timezone == referenceTimezone && $0.metric == referenceMetric }.max { $0.importedAt < $1.importedAt }
        do { try store?.addReference(ReferenceTotal(day: key, timezone: referenceTimezone, metric: referenceMetric, seconds: referenceHours * 3600, source: "manual", correctsID: previous?.id)); refresh() } catch { fail(error) }
    }
    func importCSV() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.commaSeparatedText, .plainText]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 2_000_000 else { throw CSVError.invalid("CSV exceeds 2 MB.") }
            var values = try CalibrationCSV.parse(String(contentsOf: url, encoding: .utf8), timezone: referenceTimezone, metric: referenceMetric)
            for index in values.indices {
                values[index].correctsID = references.filter { $0.day == values[index].day && $0.timezone == referenceTimezone && $0.metric == referenceMetric }.max { $0.importedAt < $1.importedAt }?.id
            }
            try store?.importReferences(values); refresh(); message = "Imported \(values.count) daily reference totals."
        } catch { message = error.localizedDescription }
    }
    func exportCSV() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "productive-hours-summary.csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let csv = "date,timezone,productive_active_seconds,productive_passive_seconds,unknown_seconds\n" + totals.map { "\($0.id),\(settings.timezone),\(Int($0.active)),\(Int($0.passive)),\(Int($0.unknown))" }.joined(separator: "\n")
        do { try csv.write(to: url, atomically: true, encoding: .utf8); message = "Aggregated statistics exported." } catch { message = error.localizedDescription }
    }
    func deleteAll() {
        pause()
        do {
            try store?.deleteAll()
            let diagnostics = Self.directory.appending(path: "Diagnostics")
            if FileManager.default.fileExists(atPath: diagnostics.path) { try FileManager.default.removeItem(at: diagnostics) }
            settings = AppSettings(); editedSettings = settings; rules = []; engine = TrackingEngine(start: Date().epochMS); pending = []; notificationDates = [:]; snoozedUntil = nil
            trace = DiagnosticTrace(fileURL: Self.directory.appending(path: "Diagnostics/phase-0.json")); typeSnoozes = [:]; forecastAlert = ForecastAlertState()
            discordPresence.shutdown()
            error = nil; message = "Local activity, rules, references, settings and diagnostic data deleted."; refresh(); confirmDelete = false
            UNUserNotificationCenter.current().removeAllPendingNotificationRequests(); UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        } catch { fail(error) }
    }
    func setLogin(_ enabled: Bool) {
        do { if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }; loginEnabled = enabled }
        catch { message = "Launch at login could not be changed: \(error.localizedDescription)" }
    }
    func enableNotifications() {
        Task {
            do {
                let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
                editedSettings.notifications = granted; settings.notifications = granted
                try store?.save("settings", value: settings)
                if !granted { message = "Notifications are disabled in System Settings. Tracking still works." }
                else { message = "Notification permission granted." }
            } catch { message = "Notification authorization unavailable. Tracking still works." }
        }
    }
    private func syncNotificationAuthorization() {
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] status in
            let authorized = status.authorizationStatus == .authorized || status.authorizationStatus == .provisional
            Task { @MainActor in
                guard let self else { return }
                if self.settings.notifications && !authorized {
                    self.settings.notifications = authorized
                    self.editedSettings.notifications = authorized
                    try? self.store?.save("settings", value: self.settings)
                    if !authorized {
                        self.message = "Alerts are enabled in Worktempo but macOS has not granted notification permission. Use Authorize notifications."
                    }
                }
            }
        }
    }
    func snooze() { snoozedUntil = settings.calendar.date(byAdding: .day, value: 1, to: Date()); try? store?.save("snoozedUntil", value: snoozedUntil) }
    func snooze(type: String) {
        typeSnoozes[type] = Date().addingTimeInterval(86400)
        do { try store?.save("typeSnoozes", value: typeSnoozes); message = "This alert type is snoozed for 24 hours." }
        catch { message = "Could not save alert snooze." }
    }
    private func evaluateNotifications() {
        let now = Date()
        let week = liveWeek
        let forecast = forecastAlert.evaluate(projection: week.projection, minimum: week.minimum, maximum: week.maximum, now: now)
        do { try store?.save("forecastAlert", value: forecastAlert) } catch { message = "Could not save forecast alert state." }
        guard NotificationPolicy.canDeliver(now: now, settings: settings, lastSent: nil, snoozedUntil: snoozedUntil) else { return }
        var type: String?, body = ""
        if error != nil { type = "collection_stopped"; body = "Collection stopped. Open Worktempo to review the data gap." }
        else if menuTitle == "Limited coverage" { type = "coverage_degraded"; body = "Browser coverage is limited. Review browser access and classifications." }
        else if week.productive >= week.maximum { type = "maximum_reached"; body = "Your estimated productive time reached the weekly maximum." }
        else if week.productive >= week.minimum { type = "minimum_reached"; body = "Your estimated productive time reached the weekly minimum." }
        else if let forecast, let projection = week.projection, settings.calendar.component(.hour, from: now) >= settings.endHour {
            type = forecast; body = "Based on recent activity, projected weekly productive time is \(Metrics.duration(projection)). Your target is \(Metrics.duration(week.minimum))–\(Metrics.duration(week.maximum))."
        }
        guard let type else { return }
        let key = type + ":" + Metrics.dayKey(now, calendar: settings.calendar)
        guard NotificationPolicy.canDeliver(now: now, settings: settings, lastSent: notificationDates[key], snoozedUntil: max(snoozedUntil ?? .distantPast, typeSnoozes[type] ?? .distantPast)) else { return }
        notificationDates = notificationDates.filter { now.timeIntervalSince($0.value) < 32 * 86400 }
        notificationDates[key] = now
        do { try store?.save("notificationDates", value: notificationDates) } catch { message = "Could not save notification cooldown."; return }
        let content = UNMutableNotificationContent(); content.title = "Worktempo · Estimate"; content.body = body
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: key, content: content, trigger: nil))
    }
    private func evaluateActivityTransition(now: Date) {
        let eligible = running && error == nil && !engine.paused && engine.healthy
        guard let transition = activityTransition.evaluate(current: engine.state, eligible: eligible) else { return }
        switch transition {
        case .enteredPassive:
            guard settings.warnWhenEnteringPassive else { return }
            guard activityNotificationAllowed(type: "activity_passive", now: now) else { return }
            deliverImmediateNotification(
                identifier: "activity_passive",
                title: "Worktempo · Passive time",
                body: "Activity is now passive. You can still earn productive credit during the passive window if the app is classified as productive.")
        case .enteredInactive:
            guard settings.warnWhenEnteringInactive else { return }
            guard activityNotificationAllowed(type: "activity_inactive", now: now) else { return }
            deliverImmediateNotification(
                identifier: "activity_inactive",
                title: "Worktempo · Inactive",
                body: "Activity is now inactive. Keyboard and mouse presence no longer count toward productive time until you interact again.")
        }
    }
    private func activityNotificationAllowed(type: String, now: Date) -> Bool {
        let snooze = max(snoozedUntil ?? .distantPast, typeSnoozes[type] ?? .distantPast)
        return NotificationPolicy.canDeliverActivityAlert(now: now, settings: settings, snoozedUntil: snooze)
    }
    private func deliverImmediateNotification(identifier: String, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil))
    }

    private func evaluateAdvanceModeWarnings(idleMS: Int64?, now: Date) {
        let activeMS = Int64(settings.activeMinutes) * 60_000
        let passiveMS = Int64(settings.passiveMinutes) * 60_000
        let baseEligible = running && error == nil && engine.healthy && !engine.paused && engine.barriers.isEmpty
        let passiveEligible = baseEligible && engine.state == .active && !engine.isCallCrediting
            && activityNotificationAllowed(type: "before_passive", now: now)
        let inactiveEligible = baseEligible && engine.state == .passive && !engine.isCallCrediting
            && activityNotificationAllowed(type: "before_inactive", now: now)
        let advance = advanceModeWarning.evaluate(
            idleMS: idleMS,
            activeMS: activeMS,
            passiveMS: passiveMS,
            warnBeforePassiveSeconds: settings.effectiveWarnBeforePassiveSeconds,
            warnBeforeInactiveSeconds: settings.effectiveWarnBeforeInactiveSeconds,
            passiveEligible: passiveEligible,
            inactiveEligible: inactiveEligible)
        if advance.beforePassive {
            let remaining = max(1, settings.activeMinutes * 60 - Int((idleMS ?? 0) / 1000))
            deliverImmediateNotification(
                identifier: "before_passive",
                title: "Worktempo · Passive soon",
                body: "Passive time starts in about \(remaining) seconds. Mouse or keyboard activity resets the idle timer.")
        }
        if advance.beforeInactive {
            let boundary = settings.activeMinutes * 60 + settings.passiveMinutes * 60
            let remaining = max(1, boundary - Int((idleMS ?? 0) / 1000))
            deliverImmediateNotification(
                identifier: "before_inactive",
                title: "Worktempo · Inactive soon",
                body: "Inactive time starts in about \(remaining) seconds. Productive credit from presence will stop until you interact again.")
        }
    }
}

private struct MeetingCheckpoint: Codable { var start: Date; var lastConfirmed: Date }
