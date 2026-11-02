import Foundation
import ActivityCore

public struct BrowserObservation: Sendable {
    public var app: String
    public var host: String?
    public var status: String
    public var observedAt: Date
}

/// Opt-in public browser scripting. Raw URL is transient and never logged or persisted.
public actor BrowserObserver {
    public init() {}
    public static let browsers: Set<String> = ["com.google.Chrome", "com.microsoft.edgemac", "com.apple.Safari", "company.thebrowser.Browser", "org.mozilla.firefox", "com.brave.Browser"]
    static let supportedBrowsers: Set<String> = ["com.google.Chrome", "com.microsoft.edgemac", "company.thebrowser.Browser"]
    public func observe(app: String) -> BrowserObservation {
        let now = Date()
        guard Self.supportedBrowsers.contains(app) else {
            return BrowserObservation(app: app, host: nil, status: "Browser not supported by native adapter", observedAt: now)
        }
        let script = """
        tell application id "\(app)"
            if frontmost is false then return ""
            if (count of windows) is 0 then return ""
            if mode of front window is "incognito" then return "PRIVATE"
            return URL of active tab of front window
        end tell
        """
        var error: NSDictionary?
        let result = NSAppleScript(source: script)?.executeAndReturnError(&error).stringValue
        guard error == nil, let result else { return BrowserObservation(app: app, host: nil, status: "Browser access unavailable. Check Automation permission.", observedAt: now) }
        if result == "PRIVATE" { return BrowserObservation(app: app, host: nil, status: "Private browsing excluded", observedAt: now) }
        guard let url = URLComponents(string: result), ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host.flatMap(RuleEvaluator.hostname) else {
            return BrowserObservation(app: app, host: nil, status: "No supported website", observedAt: now)
        }
        return BrowserObservation(app: app, host: host, status: "Hostname available", observedAt: now)
    }
}
