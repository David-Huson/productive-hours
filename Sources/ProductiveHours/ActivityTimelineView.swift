import SwiftUI
import Combine
import ActivityCore
import TimelinePresentation

@MainActor private final class TimelineViewState: ObservableObject {
    @Published var from = Date()
    @Published var through = Date()
    @Published var days: [TimelineDay] = []
    @Published var revision = UUID()
    @Published var command = 0
    var action = "fit"
    var initialized = false
    func navigate(_ action: String) { self.action = action; command += 1 }
    func reload(_ intervals: [Interval], settings: AppSettings) {
        days = ActivityTimeline.days(intervals: intervals, from: from, through: through, calendar: settings.calendar)
        revision = UUID()
    }
}

struct ActivityTimelineView: View {
    @ObservedObject var service: TrackingService
    @StateObject private var model = TimelineViewState()
    private var calendar: Calendar { service.settings.calendar }
    private func reload() { model.reload(service.intervals, settings: service.settings) }
    private func thisWeek() {
        let now = Date()
        model.from = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? calendar.startOfDay(for: now)
        model.through = now
        model.navigate("fit")
        reload()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                DatePicker("From", selection: $model.from, displayedComponents: .date)
                DatePicker("Through", selection: $model.through, displayedComponents: .date)
                Button("This week") { thisWeek() }
                Spacer()
                Text(service.settings.timezone).font(.caption).foregroundStyle(.secondary)
            }
            ScrollView(.horizontal) {
                HStack(spacing: 16) {
                    ForEach(TimelineCategory.allCases, id: \.self) { category in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 5) {
                                Circle().fill(Color(nsColor: category.color)).frame(width: 8, height: 8)
                                Text(category.rawValue).font(.caption)
                            }
                            let seconds = model.days.reduce(0) { $0 + $1.totals[category, default: 0] }
                            Text(Metrics.duration(seconds)).font(.headline).monospacedDigit()
                                .help("\(Int(seconds) / 3600)h \(Int(seconds) % 3600 / 60)m \(Int(seconds) % 60)s")
                        }.padding(8)
                    }
                }
            }
            HStack {
                Text("Daily activity").font(.headline)
                Spacer()
                Button { model.navigate("out") } label: { Image(systemName: "minus.magnifyingglass") }.help("Zoom out")
                Button { model.navigate("in") } label: { Image(systemName: "plus.magnifyingglass") }.help("Zoom in")
                Button("Fit day") { model.navigate("fit") }
                Button { model.navigate("left") } label: { Image(systemName: "chevron.left") }.help("Earlier")
                Button { model.navigate("right") } label: { Image(systemName: "chevron.right") }.help("Later")
            }
            ScrollView(.vertical) {
                TimelineChart(days: model.days, revision: model.revision, settings: service.settings,
                              rules: service.rules, command: model.command, action: model.action)
                    .frame(maxWidth: .infinity)
                    .frame(height: CGFloat(model.days.count) * 74 + 16)
                    .accessibilityLabel("Daily activity timeline. Hover segments for exact times and sources. Use zoom and pan controls to inspect events.")
            }.background(Color(nsColor: .windowBackgroundColor))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.secondary.opacity(0.2)))
            Text("Hover for details · Pinch to zoom · Drag or scroll horizontally to pan · Vertical lines mark your work schedule")
                .font(.caption).foregroundStyle(.secondary)
            Text("Up to 31 days of retained observations. Blank space means no interval is stored, not inactive time. Manual meetings and expired detail are not shown.")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(16)
        .onAppear { if !model.initialized { model.initialized = true; thisWeek() } }
        .onReceive(service.$intervals) { rows in model.reload(rows, settings: service.settings) }
        .onChange(of: service.settings) { reload() }
        .onChange(of: service.rules) { reload() }
        .onChange(of: model.from) {
            if model.through < model.from { model.through = model.from }
            if let limit = calendar.date(byAdding: .day, value: 30, to: model.from), model.through > limit { model.through = limit }
            reload()
        }
        .onChange(of: model.through) {
            if model.from > model.through { model.from = model.through }
            if let limit = calendar.date(byAdding: .day, value: -30, to: model.through), model.from < limit { model.from = limit }
            reload()
        }
    }
}
