import Testing
@testable import ActivityCore

@Test func menuBarIndicatorPrefersUnproductiveOverActivity() {
    let indicator = MenuBarActivityIndicatorPolicy.resolve(
        running: true, hasError: false, productivity: .unproductive, activity: .active)
    #expect(indicator == .unproductive)
}

@Test func menuBarIndicatorMapsActivityWhenNotUnproductive() {
    #expect(MenuBarActivityIndicatorPolicy.resolve(
        running: true, hasError: false, productivity: .productive, activity: .active) == .active)
    #expect(MenuBarActivityIndicatorPolicy.resolve(
        running: true, hasError: false, productivity: .productive, activity: .passive) == .passive)
    #expect(MenuBarActivityIndicatorPolicy.resolve(
        running: true, hasError: false, productivity: .undefined, activity: .inactive) == .inactive)
}

@Test func menuBarIndicatorHiddenWhenPausedOrUnknown() {
    #expect(MenuBarActivityIndicatorPolicy.resolve(
        running: false, hasError: false, productivity: .productive, activity: .active) == .hidden)
    #expect(MenuBarActivityIndicatorPolicy.resolve(
        running: true, hasError: true, productivity: .productive, activity: .active) == .hidden)
    #expect(MenuBarActivityIndicatorPolicy.resolve(
        running: true, hasError: false, productivity: .productive, activity: .unknown) == .hidden)
}
