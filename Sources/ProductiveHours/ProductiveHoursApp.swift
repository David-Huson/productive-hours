import SwiftUI
import AppKit
import ActivityCore
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    static weak var service: TrackingService?
    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Self.service?.shutdown(); return .terminateNow
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

@main
struct ProductiveHoursApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var service = TrackingService()
    var body: some Scene {
        MenuBarExtra {
            PacePopover(service: service).onAppear { AppDelegate.service = service }
        } label: {
            Image(nsImage: service.menuBarIcon)
                .accessibilityLabel(menuBarAccessibilityLabel(for: service.menuBarActivityIndicator, title: service.menuTitle))
        }.menuBarExtraStyle(.window)
        Window("Worktempo", id: "dashboard") {
            Dashboard(service: service).onAppear { AppDelegate.service = service }
        }.defaultSize(width: 1000, height: 720)
        Settings { SettingsView(service: service).frame(width: 720, height: 650) }
    }
}

private func menuBarAccessibilityLabel(for indicator: MenuBarActivityIndicator, title: String) -> String {
    let state: String
    switch indicator {
    case .active: state = "Active"
    case .passive: state = "Passive"
    case .inactive: state = "Inactive"
    case .unproductive: state = "Unproductive"
    case .hidden: state = title
    }
    if indicator == .hidden { return "Worktempo: \(title)" }
    return "Worktempo: \(state)"
}

struct PacePopover: View {
    @ObservedObject var service: TrackingService
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        let now = Date()
        let calendar = service.settings.calendar
        let week = Metrics.week(containing: now, now: now, totals: service.totals, settings: service.settings)
        let today = service.totals.first { calendar.isDate($0.date, inSameDayAs: now) }?.productive ?? 0
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Worktempo").font(.headline)
                Spacer()
                Text("Productive time").font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                total("Today", seconds: today)
                total("This week", seconds: week.productive)
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Weekly target").foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Metrics.duration(week.minimum))–\(Metrics.duration(week.maximum))").monospacedDigit()
                }.font(.caption)
                ProgressView(value: min(week.productive, week.minimum), total: max(1, week.minimum))
                    .accessibilityLabel("Progress toward weekly minimum")
                    .accessibilityValue("\(Metrics.duration(week.productive)) of \(Metrics.duration(week.minimum))")
                Text(week.remaining > 0
                     ? "\(Metrics.duration(week.remaining)) to weekly minimum"
                     : "Weekly minimum reached")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                Text("Current pace").font(.caption).foregroundStyle(.secondary)
                Text(week.status).font(.title2.weight(.semibold))
                if week.scheduledCapacity > 0 {
                    Text("Expected by now: \(Metrics.duration(week.expectedMinimum))–\(Metrics.duration(week.expectedMaximum))")
                        .font(.callout).foregroundStyle(.secondary)
                    Text("Based on your target and elapsed work schedule.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Choose workdays and hours in Settings to calculate pace.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            if service.menuTitle != service.stablePace {
                Label(service.menuTitle, systemImage: service.menuSymbol).font(.callout.weight(.medium))
                Text(service.advice).font(.caption).foregroundStyle(.secondary)
            }
            if service.isCallCrediting {
                Label("Work call counted", systemImage: "phone.fill").font(.caption)
            }
            if let end = service.meetingEnd {
                Text("Work meeting until \(end.formatted(date: .omitted, time: .shortened)) · separately recorded")
                Button("End meeting") { service.endMeeting() }
            }
            Button("Open dashboard") { openWindow(id: "dashboard"); NSApplication.shared.activate(ignoringOtherApps: true) }
                .buttonStyle(.borderedProminent).keyboardShortcut("d")
            HStack {
                Button(service.running ? "Pause tracking" : "Resume tracking") { service.running ? service.pause() : service.start() }
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }.keyboardShortcut("q")
            }
            Text("Estimated productive digital time · stored on this Mac").font(.caption).foregroundStyle(.secondary)
        }.padding(20).frame(width: 360)
    }

    private func total(_ title: String, seconds: Double) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(Metrics.duration(seconds)).font(.title2.weight(.semibold)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
    }
}
