import SwiftUI
import AppKit
import Charts
import Combine
import ActivityCore

struct Dashboard: View {
    @ObservedObject var service: TrackingService
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable().scaledToFit().frame(width: 56, height: 56)
                    .accessibilityHidden(true)
                VStack(alignment: .leading) {
                    Text("Worktempo").font(.largeTitle.bold())
                    Text("Your time, estimated locally").foregroundStyle(.secondary)
                }
                Spacer()
                Label(service.menuTitle, systemImage: service.menuSymbol)
                Button(service.running ? "Pause" : "Start tracking") { service.running ? service.pause() : service.start() }
                    .buttonStyle(.borderedProminent)
            }.padding(24)
            if let error = service.error {
                HStack { Text(error).foregroundStyle(.red); Spacer(); Button("Retry storage") { service.retryStorage() } }.padding(.horizontal, 24)
            }
            if let message = service.message {
                HStack { Text(message).font(.callout); Spacer(); Button("Dismiss") { service.message = nil } }.padding(.horizontal, 24)
            }
            TabView {
                OverviewView(service: service).tabItem { Label("Overview", systemImage: "chart.bar") }
                HistoryView(service: service).tabItem { Label("History", systemImage: "calendar") }
                ActivityTimelineView(service: service).tabItem { Label("Timeline", systemImage: "chart.bar.xaxis") }
                RulesView(service: service).tabItem { Label("Classifications", systemImage: "tag") }
                CalibrationView(service: service).tabItem { Label("Calibration", systemImage: "equal.circle") }
                SettingsView(service: service).tabItem { Label("Settings", systemImage: "gearshape") }
            }.environment(\.calendar, service.settings.calendar).environment(\.timeZone, service.settings.calendar.timeZone).padding([.horizontal, .bottom], 16)
        }.frame(minWidth: 850, minHeight: 620)
    }
}

struct MetricCard: View {
    var title: String
    var value: String
    var detail: String = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.callout).foregroundStyle(.secondary)
            Text(value).font(.title2.monospacedDigit().weight(.semibold))
            if !detail.isEmpty { Text(detail).font(.caption).foregroundStyle(.secondary) }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
            .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct WeekPicker: View {
    @ObservedObject var service: TrackingService
    var body: some View {
        HStack {
            Button { service.weekOffset -= 1 } label: { Image(systemName: "chevron.left") }.accessibilityLabel("Previous week")
            Text("Week of \(Metrics.dayLabel(service.week.start, calendar: service.settings.calendar))").font(.headline)
            Button { service.weekOffset += 1 } label: { Image(systemName: "chevron.right") }.disabled(service.weekOffset >= 0).accessibilityLabel("Next week")
            Spacer()
            Button("This week") { service.weekOffset = 0 }
        }
    }
}

struct OverviewView: View {
    @ObservedObject var service: TrackingService
    var body: some View {
        let week = service.week
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if !service.settings.monitoringEnabled && service.intervals.isEmpty {
                    GroupBox("Welcome") {
                        Text("Enable tracking only on a device where you are permitted to do so. This app observes foreground app identifiers and elapsed input-idle time. It does not record keys, content or screenshots. Browser access is optional. Review your schedule and classify work apps before expecting productive totals.")
                            .padding(8)
                    }
                }
                WeekPicker(service: service)
                let today = service.totals.first { service.settings.calendar.isDateInToday($0.date) }
                Text("Today: \(Metrics.duration(today?.productive ?? 0)) estimated productive").font(.headline)
                HStack {
                    MetricCard(title: "Estimated productive", value: Metrics.duration(week.productive), detail: "Target \(Int(service.settings.minimumHours))–\(Int(service.settings.maximumHours))h")
                    MetricCard(title: "To minimum", value: Metrics.duration(week.remaining), detail: week.remaining == 0 ? "Minimum met" : "Productive digital time")
                    MetricCard(title: week.overage > 0 ? "Above maximum" : "Headroom", value: Metrics.duration(week.overage > 0 ? week.overage : week.headroom))
                }
                Chart {
                    BarMark(x: .value("Hours", week.productive / 3600)).foregroundStyle(.blue)
                    RuleMark(x: .value("Minimum", service.settings.minimumHours)).foregroundStyle(.green).annotation(position: .top) { Text("Minimum").font(.caption) }
                    RuleMark(x: .value("Maximum", service.settings.maximumHours)).foregroundStyle(.orange).annotation(position: .top) { Text("Maximum").font(.caption) }
                }.chartXScale(domain: 0...max(service.settings.maximumHours * 1.1, week.productive / 3600)).frame(height: 65)
                    .accessibilityLabel("Estimated productive \(Metrics.duration(week.productive)); minimum \(Int(service.settings.minimumHours)) hours, maximum \(Int(service.settings.maximumHours)) hours")
                HStack {
                    MetricCard(title: "Productive active", value: Metrics.duration(week.days.reduce(0) { $0 + $1.active }))
                    MetricCard(title: "Productive passive", value: Metrics.duration(week.days.reduce(0) { $0 + $1.passive }))
                    MetricCard(title: "Untracked time", value: Metrics.duration(week.unknown), detail: "Paused or collection unavailable")
                }
                DisclosureGroup("Why time is untracked") {
                    let gaps = TrackingGapSummary(intervals: service.intervals, start: week.start, end: week.end)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Tracking paused: \(Metrics.duration(gaps.paused))")
                        Text("Collection unavailable: \(Metrics.duration(gaps.collection))")
                        let other = gaps.other + max(0, week.unknown - gaps.total)
                        if other > 0 { Text("Other / archived gaps: \(Metrics.duration(other))") }
                        Text("Untracked time has no reliable activity measurement. It includes pauses and may include app restarts. It cannot be fixed with classification rules and is not counted as productive or unproductive. Totals cover the selected week, including outside your work schedule.")
                            .font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
                }
                GroupBox("Weekly pace") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(week.status).font(.headline)
                        WeekBurnupChart(week: week, settings: service.settings).zIndex(1)
                        if week.scheduledCapacity > 0 {
                            Text("Expected by now: \(Metrics.duration(week.expectedMinimum))–\(Metrics.duration(week.expectedMaximum)) · logged: \(Metrics.duration(week.productive))")
                            Text("Pace uses your target and elapsed scheduled hours. Untracked time is not assumed productive.").font(.caption).foregroundStyle(.secondary)
                        }
                        Divider()
                        Text("Weekly forecast").font(.subheadline.weight(.semibold))
                        if let projection = week.projection {
                            Text("Projected total \(Metrics.duration(projection)) · range \(Metrics.duration(week.projectionLow ?? projection))–\(Metrics.duration(week.projectionHigh ?? projection))")
                            Text("Range uses recent daily yields, not a statistical confidence interval. \(week.usableDays) usable days; 28-day lookback with recency weighting.").font(.caption).foregroundStyle(.secondary)
                        } else {
                            Text("Forecast calibrating: needs three usable scheduled workdays and adequate coverage. Your schedule-based pace is available immediately.")
                        }
                        if week.remainingCapacity > 0 {
                            let equivalents = week.remainingCapacity / Double((service.settings.endHour - service.settings.startHour) * 3600)
                            Text("Needed per remaining workday equivalent: \(Metrics.duration(week.remaining / max(0.001, equivalents)))")
                            Text("Remaining scheduled capacity: \(Metrics.duration(week.remainingCapacity)). Includes only the unelapsed portion of today.").font(.caption)
                        } else { Text(week.remaining > 0 ? "Schedule complete; minimum not reached." : "Schedule complete.") }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
                }.zIndex(1)
                GroupBox("Work meetings") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(service.callStatus)
                        Text("Zoom and Discord audio activity counts as productive, including muted calls and listening without typing. Pause, observed lock/sleep, private browsing and ignored apps prevent credit. Other call apps can use the manual timer below.").font(.caption)
                        Text("Manual meeting time stays separate and may overlap automatic time.").font(.caption)
                        HStack {
                            if let end = service.meetingEnd {
                                Text("Meeting ends at \(end.formatted(date: .omitted, time: .shortened))")
                                Button("End now") { service.endMeeting() }
                            } else {
                                Button("Start 30-minute meeting") { service.beginMeeting(minutes: 30) }
                                Button("Start 60-minute meeting") { service.beginMeeting(minutes: 60) }
                            }
                        }
                        let seconds = service.manual.reduce(0.0) { $0 + max(0, min($1.end, week.end).timeIntervalSince(max($1.start, week.start))) }
                        Text("User-declared work this week: \(Metrics.duration(seconds)) · may overlap automatic time").font(.caption)
                    }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack {
                    Text("Current activity: \(service.currentState.rawValue) · \(service.currentApp.isEmpty ? "No app observed" : service.currentApp)")
                    Spacer()
                    Text("Updated \(service.lastUpdated.formatted(date: .omitted, time: .standard))")
                }.font(.caption).foregroundStyle(.secondary)
            }.padding(16)
        }
    }
}

private struct WeekBurnupChart: View {
    @StateObject private var hover = HistoryHover()
    let week: WeeklyMetrics
    let settings: AppSettings
    var body: some View {
        let points = Metrics.burnup(week: week, now: Date(), settings: settings)
        VStack(alignment: .leading, spacing: 6) {
            Chart {
                RectangleMark(xStart: .value("Start", week.start), xEnd: .value("End", week.end),
                              yStart: .value("Minimum", week.minimum / 3600), yEnd: .value("Maximum", week.maximum / 3600))
                    .foregroundStyle(.green.opacity(0.12))
                RuleMark(y: .value("Minimum", week.minimum / 3600)).foregroundStyle(.green.opacity(0.6))
                RuleMark(y: .value("Maximum", week.maximum / 3600)).foregroundStyle(.green.opacity(0.6))
                ForEach(points.planned) { point in
                    LineMark(x: .value("Date", point.date), y: .value("Hours", point.seconds / 3600))
                        .foregroundStyle(by: .value("Series", "Target pace"))
                        .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 4]))
                }
                ForEach(points.actual) { point in
                    LineMark(x: .value("Date", point.date), y: .value("Hours", point.seconds / 3600))
                        .foregroundStyle(by: .value("Series", "Logged productive"))
                        .lineStyle(StrokeStyle(lineWidth: 3))
                    PointMark(x: .value("Date", point.date), y: .value("Hours", point.seconds / 3600))
                        .foregroundStyle(by: .value("Series", "Logged productive"))
                }
            }
            .chartForegroundStyleScale(["Target pace": Color.secondary, "Logged productive": Color.blue])
            .chartXScale(domain: week.start...week.end)
            .chartYScale(domain: 0...max(week.maximum, week.productive) / 3600 * 1.1)
            .chartXAxis { AxisMarks(values: .stride(by: .day)) { _ in AxisValueLabel(format: .dateTime.weekday(.abbreviated)) } }
            .chartYAxisLabel("Cumulative hours")
            .environment(\.calendar, settings.calendar)
            .environment(\.timeZone, settings.calendar.timeZone)
            .frame(height: 230)
            .chartOverlay { proxy in
                ChartDayHover(proxy: proxy, calendar: settings.calendar, hover: hover)
            }
            .overlay {
                ChartHoverTooltip(hover: hover) {
                    if let day = week.days.first(where: { $0.id == hover.dayID }) {
                        let now = Date()
                        let next = settings.calendar.date(byAdding: .day, value: 1, to: day.date)!
                        let future = day.date > now
                        let cutoff = future ? next : min(next, now)
                        let planned = Metrics.week(containing: day.date, now: cutoff, totals: [], settings: settings).expectedMaximum
                        let cumulative = week.days.filter { $0.date <= day.date }.reduce(0.0) { $0 + $1.productive }
                        HistoryDayTooltip(day: day, calendar: settings.calendar,
                            cumulative: future ? nil : cumulative, planned: planned,
                            showActual: !future, period: future || next <= now ? "At day end" : "So far today")
                            .allowsHitTesting(false)
                    }
                }
            }
            .zIndex(1)
            .onChange(of: week.start) { hover.dayID = nil }
            Text("Target band: \(Metrics.duration(week.minimum))–\(Metrics.duration(week.maximum)). Dashed pace distributes the upper target across scheduled work hours; blue shows daily cumulative logged time through now.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

@MainActor
private final class HistoryHover: ObservableObject {
    @Published var dayID: String?
    @Published var point = CGPoint.zero
}

private struct ChartHoverTooltip<Content: View>: View {
    @ObservedObject var hover: HistoryHover
    @ViewBuilder var content: () -> Content
    var body: some View {
        GeometryReader { geometry in
            let width = min(340.0, geometry.size.width)
            let preferredX = hover.point.x + 16 + width <= geometry.size.width
                ? hover.point.x + 16 : hover.point.x - width - 16
            content()
                .frame(width: width)
                .fixedSize(horizontal: false, vertical: true)
                .offset(x: min(max(0, preferredX), max(0, geometry.size.width - width)),
                        y: hover.point.y + 16)
        }
        .allowsHitTesting(false)
    }
}

private struct ChartDayHover: View {
    let proxy: ChartProxy
    let calendar: Calendar
    @ObservedObject var hover: HistoryHover
    var body: some View {
        GeometryReader { geometry in
            Rectangle().fill(.clear).contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let point):
                        guard let anchor = proxy.plotFrame else { hover.dayID = nil; return }
                        let plot = geometry[anchor]
                        guard plot.contains(point), let date: Date = proxy.value(atX: point.x - plot.minX) else {
                            hover.dayID = nil; return
                        }
                        hover.point = point
                        hover.dayID = Metrics.dayKey(date, calendar: calendar)
                    case .ended: hover.dayID = nil
                    }
                }
        }
    }
}

struct HistoryView: View {
    @ObservedObject var service: TrackingService
    @StateObject private var hover = HistoryHover()
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                WeekPicker(service: service)
                Chart(service.week.days) { day in
                    BarMark(x: .value("Day", day.date, unit: .day), y: .value("Hours", day.active / 3600)).foregroundStyle(by: .value("Activity", "Active"))
                    BarMark(x: .value("Day", day.date, unit: .day), y: .value("Hours", day.passive / 3600)).foregroundStyle(by: .value("Activity", "Passive"))
                }.frame(height: 210).chartForegroundStyleScale(["Active": Color.blue, "Passive": Color.teal])
                .environment(\.calendar, service.settings.calendar)
                .environment(\.timeZone, service.settings.calendar.timeZone)
                .chartOverlay { proxy in
                    ChartDayHover(proxy: proxy, calendar: service.settings.calendar, hover: hover)
                }
                .overlay {
                    ChartHoverTooltip(hover: hover) {
                        if let day = service.week.days.first(where: { $0.id == hover.dayID }) {
                            HistoryDayTooltip(day: day, calendar: service.settings.calendar)
                                .allowsHitTesting(false)
                        }
                    }
                }
                .zIndex(1)
                .onChange(of: service.weekOffset) { hover.dayID = nil }
                ForEach(service.week.days) { day in
                    DisclosureGroup {
                        Text("Unproductive \(Metrics.duration(day.unproductive)) · Undefined \(Metrics.duration(day.undefined)) · Ignored \(Metrics.duration(day.ignored)) · Inactive \(Metrics.duration(day.inactive)) · Unknown \(Metrics.duration(day.unknown))")
                            .font(.callout).frame(maxWidth: .infinity, alignment: .leading).padding(6)
                        let next = service.settings.calendar.date(byAdding: .day, value: 1, to: day.date)!
                        let rows = service.intervals.filter { $0.start < next.epochMS && $0.end > day.date.epochMS }
                        let groups = Dictionary(grouping: rows) { service.activityLabel(for: $0.source) }
                        let titles = groups.keys.sorted { lhs, rhs in
                            let left = groups[lhs, default: []].reduce(0.0) { $0 + Double(min($1.end, next.epochMS) - max($1.start, day.date.epochMS)) / 1000 }
                            let right = groups[rhs, default: []].reduce(0.0) { $0 + Double(min($1.end, next.epochMS) - max($1.start, day.date.epochMS)) / 1000 }
                            return left == right ? lhs.localizedStandardCompare(rhs) == .orderedAscending : left > right
                        }
                        ForEach(titles, id: \.self) { title in
                            let rows = groups[title, default: []]
                            let seconds = rows.reduce(0.0) { $0 + Double(min($1.end, next.epochMS) - max($1.start, day.date.epochMS)) / 1000 }
                            HStack { Text(title); Spacer(); Text(Metrics.duration(seconds)) }.font(.caption)
                        }
                    } label: {
                        HStack { Text(Metrics.dayLabel(day.date, calendar: service.settings.calendar)); Spacer(); Text(Metrics.duration(day.productive)).monospacedDigit() }
                    }
                    Divider()
                }
                Text("Older retained summaries may have no app detail. Changing timezone cannot reconstruct expired raw intervals.").font(.caption).foregroundStyle(.secondary)
                Button("Export aggregated statistics…") { service.exportCSV() }
            }.padding(16)
        }
    }
}

private struct HistoryDayTooltip: View {
    let day: DayTotal
    let calendar: Calendar
    var cumulative: Double? = nil
    var planned: Double? = nil
    var showActual = true
    var period: String? = nil

    private func hours(_ seconds: Double) -> String {
        let whole = Int(max(0, seconds).rounded())
        let clock = String(format: "%d:%02d:%02d", whole / 3600, (whole % 3600) / 60, whole % 60)
        return String(format: "%.3f h", seconds / 3600) + " (" + clock + ")"
    }

    private func row(_ title: String, _ seconds: Double) -> some View {
        HStack {
            Text(title)
            Spacer(minLength: 12)
            Text(hours(seconds)).monospacedDigit()
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(Metrics.dayLabel(day.date, calendar: calendar)).fontWeight(.semibold)
            if let period { Text(period).foregroundStyle(.secondary) }
            if let cumulative { row("Cumulative productive", cumulative).fontWeight(.semibold) }
            if let planned { row("Planned cumulative", planned) }
            if planned != nil { Divider() }
            if showActual {
                row("Day productive total", day.productive).fontWeight(.semibold)
                row("Productive active", day.active)
                row("Productive passive", day.passive)
                row("Unproductive", day.unproductive)
                row("Undefined", day.undefined)
                row("Ignored", day.ignored)
                row("Inactive", day.inactive)
                row("Unknown / gaps", day.unknown)
            } else { Text("Future day · no actual hours yet").foregroundStyle(.secondary) }
        }
        .font(.caption)
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(Color(nsColor: .windowBackgroundColor).opacity(1), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.secondary.opacity(0.25)))
        .shadow(radius: 4, y: 2)
        .accessibilityElement(children: .combine)
    }
}

@MainActor
private final class RuleEditState: ObservableObject {
    @Published var draft: ClassificationRule
    @Published var displayNameText: String
    init(_ rule: ClassificationRule) {
        draft = rule
        displayNameText = rule.displayName ?? ""
    }
}

private struct EditableRuleRow: View {
    @ObservedObject var service: TrackingService
    let rule: ClassificationRule
    @StateObject private var edit: RuleEditState

    init(service: TrackingService, rule: ClassificationRule) {
        self.service = service
        self.rule = rule
        _edit = StateObject(wrappedValue: RuleEditState(rule))
    }

    private var draftChanged: Bool {
        edit.draft != rule || edit.displayNameText.trimmingCharacters(in: .whitespacesAndNewlines) != (rule.displayName ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Display name", text: $edit.displayNameText)
            HStack(spacing: 8) {
                Picker("Type", selection: $edit.draft.kind) {
                    ForEach(ClassificationRule.Kind.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.frame(width: 130)
                TextField(edit.draft.kind == .app ? "Bundle ID" : "Hostname", text: $edit.draft.pattern)
                Picker("Class", selection: $edit.draft.productivity) {
                    ForEach(ProductivityClass.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.frame(width: 140)
                Stepper("Priority \(edit.draft.priority)", value: $edit.draft.priority, in: -100...100).frame(width: 130)
            }
            HStack {
                Toggle("Enabled", isOn: $edit.draft.enabled)
                Spacer()
                Text("v\(edit.draft.version) · \(edit.draft.pattern)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Button("Save") { commit() }.disabled(!draftChanged)
                Button("Revert") { revert() }.disabled(!draftChanged)
                Button("Remove", role: .destructive) { service.removeRule(rule.id) }
            }
        }
        .padding(.vertical, 4)
        .onChange(of: rule) { _, fresh in
            guard !draftChanged else { return }
            edit.draft = fresh
            edit.displayNameText = fresh.displayName ?? ""
        }
    }

    private func revert() {
        edit.draft = rule
        edit.displayNameText = rule.displayName ?? ""
    }

    private func commit() {
        var updated = edit.draft
        let trimmed = edit.displayNameText.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.displayName = trimmed.isEmpty ? nil : trimmed
        service.updateRule(updated)
        if let saved = service.rules.first(where: { $0.id == rule.id }) {
            edit.draft = saved
            edit.displayNameText = saved.displayName ?? ""
        }
    }
}

struct RulesView: View {
    @ObservedObject var service: TrackingService
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Untracked time is shown on Overview and History. This tab lists recorded activity that needs a classification rule; pauses and collection gaps cannot be classified.").font(.caption).foregroundStyle(.secondary)
            Text("Rules apply forward by default. Exact host → scoped subdomain → domain → app → Undefined. Higher priority wins ties.").font(.callout)
            Text("Display names are for your reference only; matching still uses the pattern.").font(.caption).foregroundStyle(.secondary)
            HStack {
                TextField("Display name", text: $service.ruleDisplayName).frame(minWidth: 120)
                Picker("Type", selection: $service.ruleKind) { ForEach(ClassificationRule.Kind.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.frame(width: 130)
                TextField(service.ruleKind == .app ? "com.example.app" : "example.com", text: $service.rulePattern)
                Picker("Class", selection: $service.ruleClass) { ForEach(ProductivityClass.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.frame(width: 150)
                Stepper("Priority \(service.rulePriority)", value: $service.rulePriority, in: -100...100).frame(width: 130)
                Button("Add rule") { service.addRule() }
            }
            List {
                Section("Rules") {
                    ForEach(service.rules) { rule in
                        EditableRuleRow(service: service, rule: rule)
                    }
                }
                Section("Rule change history") {
                    ForEach(service.ruleRevisions.prefix(30)) { revision in
                        DisclosureGroup("\(revision.date.formatted()) · \(revision.action)") {
                            ForEach(revision.rules) { rule in
                                Text("\(rule.label) (\(rule.pattern)) → \(rule.productivity.rawValue) · v\(rule.version)").font(.caption)
                            }
                        }
                    }
                }
                Section("Undefined activities · largest first") {
                    let grouped = Dictionary(grouping: service.intervals.filter { $0.source.productivity == .undefined && ($0.activity == .active || $0.activity == .passive) }, by: { $0.source.host ?? $0.source.app })
                    let sorted = grouped.keys.sorted { grouped[$0, default: []].reduce(0) { $0 + $1.seconds } > grouped[$1, default: []].reduce(0) { $0 + $1.seconds } }
                    ForEach(sorted.filter { !$0.isEmpty }, id: \.self) { key in
                        let sample = grouped[key]?.first
                        let title = sample.map { service.activityLabel(for: $0.source) } ?? key
                        HStack {
                            Text(title)
                            Spacer()
                            Text(Metrics.duration(grouped[key, default: []].reduce(0) { $0 + $1.seconds }))
                            Button("Classify") {
                                service.rulePattern = sample?.source.host ?? key
                                service.ruleKind = sample?.source.host == nil ? .app : .exactHost
                                service.ruleDisplayName = ""
                            }
                        }
                    }
                }
            }
            HStack {
                Button("Preview historical recalculation") { service.previewReclassification() }
                Button("Undo last recalculation") { service.undoReclassification() }
            }
            if let preview = service.preview {
                Text("Retained productive time: \(Metrics.duration(preview.before)) → \(Metrics.duration(preview.after))")
                Text("All retained activity is recalculated using all saved rules, not just the last rule edited. Archived summaries are unchanged. You can undo an applied recalculation.")
                    .font(.caption).foregroundStyle(.secondary)
                if preview.changes.isEmpty {
                    Text("No change to productive time.").font(.callout)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(preview.changes) { change in
                                HStack {
                                    Text(service.activityLabel(for: change.source))
                                    Spacer()
                                    Text("\(change.delta < 0 ? "−" : "+")\(Metrics.duration(abs(change.delta)))").monospacedDigit()
                                }
                            }
                        }
                    }.frame(maxHeight: 140)
                }
                HStack { Button("Apply to retained history") { service.applyReclassification() }; Button("Cancel") { service.preview = nil } }
            }
        }.padding(16)
    }
}

struct CalibrationView: View {
    @ObservedObject var service: TrackingService
    private var comparisonSummary: ComparisonSummary {
        var settings = service.settings; settings.timezone = service.referenceTimezone
        let local = settings.timezone == service.settings.timezone ? service.totals : Metrics.aggregate(service.intervals, settings: settings)
        let week = settings.calendar.dateInterval(of: .weekOfYear, for: service.referenceDate)!
        let days = local.filter { $0.date >= week.start && $0.date < week.end }
        return ComparisonSummary.calculate(references: service.references, days: days, metric: service.referenceMetric, timezone: service.referenceTimezone)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Compare voluntarily supplied totals. No employer credentials or hidden configuration access.").foregroundStyle(.secondary)
            HStack {
                DatePicker("Day", selection: $service.referenceDate, displayedComponents: .date).environment(\.timeZone, TimeZone(identifier: service.referenceTimezone) ?? .current)
                TextField("Hours", value: $service.referenceHours, format: .number).frame(width: 80)
                Text("hours")
                Picker("Metric", selection: $service.referenceMetric) { Text("Productive").tag("Productive"); Text("Productive Active").tag("Productive Active") }.frame(width: 240)
            }
            HStack {
                TextField("Reference IANA timezone", text: $service.referenceTimezone)
                Button("Record total / correction") { service.saveReference() }
                Button("Import CSV…") { service.importCSV() }
            }
            Text("CSV columns: date,productive_seconds. Corrections create new reference records; originals remain preserved.").font(.caption)
            let summary = comparisonSummary
            if summary.count > 0 {
                HStack {
                    MetricCard(title: "Matched days in selected week", value: String(summary.count))
                    MetricCard(title: "Total discrepancy", value: "\(summary.delta >= 0 ? "+" : "−")\(Metrics.duration(abs(summary.delta)))", detail: summary.percentage.map { String(format: "%+.1f%%", $0) } ?? "Percentage N/A")
                    MetricCard(title: "Median daily absolute error", value: Metrics.duration(summary.medianAbsoluteDailyError))
                }
            }
            List {
                let corrected = Set(service.references.compactMap(\.correctsID))
                let refs = service.references.filter { !corrected.contains($0.id) }.sorted { $0.day > $1.day }
                ForEach(refs) { reference in
                    var settings = service.settings
                    let _ = settings.timezone = reference.timezone
                    let local = reference.timezone == service.settings.timezone ? service.totals : Metrics.aggregate(service.intervals, settings: settings)
                    let day = local.first { $0.id == reference.day }
                    let estimated = reference.metric == "Productive Active" ? day?.active : day?.productive
                    HStack {
                        VStack(alignment: .leading) { Text(reference.day); Text("\(reference.metric) · \(reference.timezone) · \(reference.source)").font(.caption).foregroundStyle(.secondary) }
                        Spacer()
                        Text("Reference \(Metrics.duration(reference.seconds))")
                        if let estimated {
                            let delta = estimated - reference.seconds
                            Text("Estimate \(Metrics.duration(estimated))")
                            Text("\(delta >= 0 ? "+" : "−")\(Metrics.duration(abs(delta)))")
                            Text(reference.seconds > 0 ? String(format: "%+.1f%%", delta / reference.seconds * 100) : "Percentage N/A")
                        } else { Text("No matching local coverage").foregroundStyle(.secondary) }
                    }
                }
            }
            Text("Differences can reflect browser gaps, classification rules, idle thresholds, timezone, other devices or offline work. A match is not guaranteed.").font(.caption)
        }.padding(16)
    }
}

struct SettingsView: View {
    @ObservedObject var service: TrackingService
    var body: some View {
        ZStack(alignment: .bottom) {
            Form {
            Section("Weekly target and schedule") {
                TextField("IANA timezone", text: $service.editedSettings.timezone)
                Picker("Week starts", selection: $service.editedSettings.weekStart) {
                    ForEach(1...7, id: \.self) { Text(Calendar.current.weekdaySymbols[$0 - 1]).tag($0) }
                }
                HStack {
                    TextField("Minimum hours", value: $service.editedSettings.minimumHours, format: .number)
                    TextField("Maximum hours", value: $service.editedSettings.maximumHours, format: .number)
                }
                HStack {
                    ForEach(1...7, id: \.self) { day in
                        Toggle(Calendar.current.shortWeekdaySymbols[day - 1], isOn: Binding(get: { service.editedSettings.workdays.contains(day) }, set: { enabled in
                            if enabled { service.editedSettings.workdays.insert(day) } else { service.editedSettings.workdays.remove(day) }
                        })).toggleStyle(.checkbox)
                    }
                }
                Stepper("Workday starts at \(service.editedSettings.startHour):00", value: $service.editedSettings.startHour, in: 0...23)
                Stepper("Workday ends at \(service.editedSettings.endHour):00", value: $service.editedSettings.endHour, in: 1...24)
            }
            Section("Activity and privacy") {
                Stepper("Passive begins after \(service.editedSettings.activeMinutes) minutes", value: $service.editedSettings.activeMinutes, in: 1...60)
                Stepper("Passive lasts \(service.editedSettings.passiveMinutes) additional minutes", value: $service.editedSettings.passiveMinutes, in: 0...120)
                Stepper("Retain detailed intervals for \(service.editedSettings.retentionDays) days", value: $service.editedSettings.retentionDays, in: 1...3650)
                Toggle("Enable Chrome / Edge / Arc hostname observation", isOn: $service.editedSettings.browserEnabled)
                Text("Uses the browser's public scripting interface with your Automation permission. Only hostnames are stored; private windows are excluded. Unsupported or blocked browsers remain Undefined unless you set an app fallback rule.").font(.caption)
                Text(service.browserStatus).font(.caption).foregroundStyle(.secondary)
                Text("No content, key codes, screen capture or outbound telemetry. Meetings you declare stay separate. Lock/display behavior still requires target-Mac verification.").font(.caption)
            }
            Section("Notifications and startup") {
                Toggle("Alerts enabled", isOn: $service.editedSettings.notifications)
                Stepper("Warn \(service.editedSettings.effectiveWarnBeforePassiveSeconds) seconds before passive", value: Binding(
                    get: { service.editedSettings.effectiveWarnBeforePassiveSeconds },
                    set: {
                        service.editedSettings.warnBeforePassiveSeconds = $0
                        service.editedSettings.idleWarningAfterSeconds = $0
                    }),
                    in: 0...(max(0, service.editedSettings.activeMinutes * 60 - 5)), step: 5)
                Stepper("Warn \(service.editedSettings.effectiveWarnBeforeInactiveSeconds) seconds before inactive", value: Binding(
                    get: { service.editedSettings.effectiveWarnBeforeInactiveSeconds },
                    set: { service.editedSettings.warnBeforeInactiveSeconds = $0 }),
                    in: 0...(max(0, service.editedSettings.passiveMinutes * 60 - 5)), step: 5)
                Text("0 disables that advance warning. Each fires once per idle episode before the boundary, then resets after input. Respects snoozes and skips during detected work calls.").font(.caption)
                Toggle("Warn when going into passive", isOn: $service.editedSettings.warnWhenEnteringPassive)
                Toggle("Warn when going into inactive", isOn: $service.editedSettings.warnWhenEnteringInactive)
                Text("Activity alerts (before/at passive or inactive) ignore quiet hours. Weekly pace alerts still respect quiet hours. All require Alerts enabled, Save settings, and macOS notification permission via Authorize.").font(.caption)
                HStack { Button("Authorize notifications…") { service.enableNotifications() }; Button("Snooze alerts for one day") { service.snooze() } }
                Menu("Snooze a specific alert for 24 hours") {
                    ForEach(["before_passive", "before_inactive", "inactivity_warning", "activity_passive", "activity_inactive", "behind_weekly_pace", "projected_over_maximum", "minimum_reached", "maximum_reached", "collection_stopped", "coverage_degraded"], id: \.self) { type in
                        Button(type.replacingOccurrences(of: "_", with: " ")) { service.snooze(type: type) }
                    }
                }
                Stepper("Quiet hours start at \(service.editedSettings.quietStart):00", value: $service.editedSettings.quietStart, in: 0...23)
                Stepper("Quiet hours end at \(service.editedSettings.quietEnd):00", value: $service.editedSettings.quietEnd, in: 0...23)
                Toggle("Launch at login", isOn: Binding(get: { service.loginEnabled }, set: { service.setLogin($0) }))
            }
            Section("Discord Rich Presence") {
                Toggle("Show activity on Discord", isOn: $service.editedSettings.discordRichPresenceEnabled)
                TextField("Application ID", text: $service.editedSettings.discordApplicationId)
                    .disabled(!service.editedSettings.discordRichPresenceEnabled)
                Toggle("Show daily total", isOn: $service.editedSettings.discordShowDailyTotal)
                    .disabled(!service.editedSettings.discordRichPresenceEnabled)
                Toggle("Show weekly total", isOn: $service.editedSettings.discordShowWeeklyTotal)
                    .disabled(!service.editedSettings.discordRichPresenceEnabled)
                Toggle("Show weekly breakdown", isOn: $service.editedSettings.discordShowWeeklyBreakdown)
                    .disabled(!service.editedSettings.discordRichPresenceEnabled)
                Text("Name your Discord application Worktempo in the Developer Portal so the profile title matches. The member list uses the status line (Worktempo: Active 🟢). Totals appear on the second line; weekly breakdown appears when you hover the artwork. Requires a recent Discord desktop client. See docs/discord-rich-presence.md.").font(.caption)
            }
            Section("Data control") {
                Button("Export aggregated statistics…") { service.exportCSV() }
                Button("Delete all local data…", role: .destructive) { service.confirmDelete = true }
                if service.confirmDelete {
                    Text("Delete activity, rules, settings, calibration, manual work and diagnostic logs? This cannot be undone.")
                    HStack { Button("Delete permanently", role: .destructive) { service.deleteAll() }; Button("Cancel") { service.confirmDelete = false } }
                }
            }
            }
            .formStyle(.grouped)
            .padding(.bottom, service.hasUnsavedSettings ? 52 : 0)
            if service.hasUnsavedSettings {
                SettingsUnsavedChangesBar(service: service)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: service.hasUnsavedSettings)
    }
}

private struct SettingsUnsavedChangesBar: View {
    @ObservedObject var service: TrackingService
    var body: some View {
        HStack(spacing: 12) {
            Text("Unsaved changes").font(.callout).foregroundStyle(.secondary)
            Spacer()
            Button("Revert") { service.discardSettingsEdits() }
            Button("Save settings") { service.saveSettings() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut("s", modifiers: .command)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial)
        .overlay(alignment: .top) { Divider() }
        .shadow(color: .black.opacity(0.12), radius: 8, y: -2)
    }
}
