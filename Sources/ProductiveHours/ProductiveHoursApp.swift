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
            Label(service.menuTitle, systemImage: service.menuSymbol)
                .accessibilityLabel("Productive Hours: \(service.menuTitle)")
        }.menuBarExtraStyle(.window)
        Window("Productive Hours", id: "dashboard") {
            Dashboard(service: service).onAppear { AppDelegate.service = service }
        }.defaultSize(width: 1000, height: 720)
        Settings { SettingsView(service: service).frame(width: 720, height: 650) }
    }
}

struct PacePopover: View {
    @ObservedObject var service: TrackingService
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(service.menuTitle, systemImage: service.menuSymbol).font(.title2.weight(.semibold))
            Text(service.advice).font(.callout).foregroundStyle(.secondary)
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
        }.padding(20).frame(width: 340)
    }
}
