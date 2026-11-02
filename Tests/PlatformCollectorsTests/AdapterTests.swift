import Testing
import ActivityCore
@testable import PlatformCollectors

@Test func nativeBrowserSupportIncludesArc() {
    #expect(BrowserObserver.supportedBrowsers.contains("company.thebrowser.Browser"))
    #expect(!BrowserObserver.supportedBrowsers.contains("org.mozilla.firefox"))
}

@Test func callProbeOnlyAttributesKnownAppsAndHelpers() {
    #expect(CallAudioProbe.callApp("us.zoom.xos") == "Zoom")
    #expect(CallAudioProbe.callApp("us.zoom.CptHost") == "Zoom")
    #expect(CallAudioProbe.callApp("com.hnc.Discord.helper") == "Discord")
    #expect(CallAudioProbe.callApp("com.hnc.DiscordImposter") == nil)
    #expect(CallAudioProbe.callApp("com.google.Chrome") == nil)
}

@Test func callCreditDoesNotRequireMicrophoneOrForeground() {
    for (input, output) in [(true, false), (false, true), (true, true)] {
        let source = CallAudioProbe.productiveSource([.init(app: "Zoom", input: input, output: output)], rules: [])
        #expect(source?.app == "us.zoom.xos")
        #expect(source?.productivity == .productive)
    }
    #expect(CallAudioProbe.productiveSource([.init(app: "Zoom", input: false, output: false)], rules: []) == nil)
    let ignored = ClassificationRule(kind: .app, pattern: "us.zoom.xos", productivity: .ignored)
    #expect(CallAudioProbe.productiveSource([.init(app: "Zoom", input: true, output: true)], rules: [ignored]) == nil)
}
