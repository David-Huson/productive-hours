import AppKit
import CoreGraphics
import ActivityCore

public struct DiagnosticObservation: Sendable {
    public let timestamp: Date
    public let event: String
    public let bundleID: String?
    public let idleMilliseconds: Int64?
    public let state: ActivityState
    public let health: ObservationHealth
    // No rules are configured in the spike. Never infer productivity from an app name.
    public var classification: ActivityClassification {
        ActivityClassification(activity: state)
    }
}

/// Explicitly started observations. The consumer owns diagnostic retention. No event taps or permission prompts.
@MainActor
public final class PlatformCollector {
    public var onObservation: ((DiagnosticObservation) -> Void)?
    private var observers: [NSObjectProtocol] = []
    private var timer: Timer?
    private var continuity = ClockContinuity()
    private var barriers: Set<String> = []
    private let idlePolicy = try! IdlePolicy()

    public init() {}

    public func start() {
        guard timer == nil else { return }
        continuity = ClockContinuity()
        barriers.removeAll()
        let center = NSWorkspace.shared.notificationCenter
        let events: [(Notification.Name, String, String?, Bool)] = [
            (NSWorkspace.didActivateApplicationNotification, "foreground_changed", nil, false),
            (NSWorkspace.didTerminateApplicationNotification, "application_terminated", nil, false),
            (NSWorkspace.willSleepNotification, "sleep", "sleep", true),
            (NSWorkspace.didWakeNotification, "wake", "sleep", false),
            (NSWorkspace.screensDidSleepNotification, "display_sleep", "display", true),
            (NSWorkspace.screensDidWakeNotification, "display_wake", "display", false),
            (NSWorkspace.sessionDidResignActiveNotification, "session_inactive", "session", true),
            (NSWorkspace.sessionDidBecomeActiveNotification, "session_active", "session", false)
        ]
        for (name, event, barrier, entering) in events {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if let barrier {
                        if entering { self.barriers.insert(barrier) }
                        else { self.barriers.remove(barrier) }
                    }
                    self.sample(event: event)
                }
            })
        }
        sample(event: "started")
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample(event: "sample") }
        }
        // Default-mode timers can stall while menus are being tracked.
        if let timer { RunLoop.main.add(timer, forMode: .common) }
    }

    public func stop() {
        if timer != nil { sample(event: "stopped") }
        timer?.invalidate()
        timer = nil
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observers.removeAll()
        barriers.removeAll()
    }

    public func sample(event: String = "sample") {
        let now = Date()
        let clock = ClockSample(
            wallMilliseconds: Int64(now.timeIntervalSince1970 * 1_000),
            monotonicMilliseconds: Int64(ProcessInfo.processInfo.systemUptime * 1_000))
        let health = continuity.observe(clock)
        // kCGAnyInputEventType is UInt32.max. `.null` is NOT the aggregate idle query.
        let aggregateSeconds = CGEventSource.secondsSinceLastEventType(
            .combinedSessionState, eventType: CGEventType(rawValue: UInt32.max)!)
        let idle: Int64? = aggregateSeconds.isFinite && aggregateSeconds >= 0 && aggregateSeconds < Double(Int64.max / 1_000)
            ? Int64(aggregateSeconds * 1_000) : nil
        let app = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let state: ActivityState
        if event == "stopped" { state = .unknown }
        else if !barriers.isEmpty { state = .inactive }
        else if health == .clockAnomaly || health == .collectionGap || app == nil { state = .unknown }
        else { state = idlePolicy.state(idleMilliseconds: idle) }
        onObservation?(DiagnosticObservation(timestamp: now, event: event, bundleID: app,
            idleMilliseconds: idle, state: state, health: health))
    }
}
