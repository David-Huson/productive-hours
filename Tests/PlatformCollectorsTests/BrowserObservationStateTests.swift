import Foundation
import Testing
@testable import PlatformCollectors

private let browserApp = "com.google.Chrome"
private let observedAt = Date(timeIntervalSince1970: 1_000)
private func website() -> BrowserObservation {
    BrowserObservation(app: browserApp, host: "work.example", status: "Hostname available", observedAt: observedAt)
}

@Test func browserHostnameExpiresAndCannotCrossAppsOrClockRollback() {
    var state = BrowserObservationState()
    state.record(website())
    #expect(state.hostname(for: browserApp, at: observedAt.addingTimeInterval(5)) == "work.example")
    #expect(state.hostname(for: browserApp, at: observedAt.addingTimeInterval(10)) == "work.example")
    #expect(state.hostname(for: browserApp, at: observedAt.addingTimeInterval(10.001)) == nil)
    #expect(state.hostname(for: browserApp, at: observedAt.addingTimeInterval(3600)) == nil)
    #expect(state.hostname(for: "com.microsoft.edgemac", at: observedAt) == nil)
    #expect(state.hostname(for: browserApp, at: observedAt.addingTimeInterval(-1)) == nil)
}

@Test(arguments: ["Browser access unavailable. Check Automation permission.", "No supported website", "Private browsing excluded", "Browser not supported by native adapter"])
func failedBrowserReadDropsPreviousHostname(status: String) {
    var state = BrowserObservationState()
    state.record(website())
    let now = observedAt.addingTimeInterval(5)
    state.record(BrowserObservation(app: browserApp, host: nil, status: status, observedAt: now))
    #expect(state.hostname(for: browserApp, at: now) == nil)
    #expect(state.latest?.status == status)
    state.record(website())
    #expect(state.hostname(for: browserApp, at: now) == "work.example")
}

@Test func browserSessionResetDropsHostnameAndPrivacyState() {
    var state = BrowserObservationState()
    state.record(website())
    state.reset()
    #expect(state.latest == nil)
    #expect(state.hostname(for: browserApp, at: observedAt) == nil)
}
