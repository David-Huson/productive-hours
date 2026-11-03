import Foundation
import Testing
@testable import ActivityCore

@Test func advanceWarningBeforePassiveFiresOnceAndRearmsAfterInput() {
    var warning = AdvanceModeWarningState()
    let active: Int64 = 120_000
    func evaluate(_ idle: Int64) -> Bool {
        warning.evaluate(idleMS: idle, activeMS: active, passiveMS: 300_000, warnBeforePassiveSeconds: 90,
            warnBeforeInactiveSeconds: 0, passiveEligible: true, inactiveEligible: false).beforePassive
    }
    #expect(!evaluate(29_999))
    #expect(evaluate(30_000))
    #expect(!evaluate(35_000))
    #expect(!evaluate(120_000))
    #expect(!evaluate(0))
    #expect(evaluate(30_000))
}

@Test func advanceWarningSkipsSuppressedUnknownDisabledAndLateSamples() {
    var warning = AdvanceModeWarningState()
    let active: Int64 = 120_000
    func evaluate(_ idle: Int64?, _ seconds: Int = 90, _ passiveEligible: Bool = true) -> Bool {
        warning.evaluate(idleMS: idle, activeMS: active, passiveMS: 300_000, warnBeforePassiveSeconds: seconds,
            warnBeforeInactiveSeconds: 0, passiveEligible: passiveEligible, inactiveEligible: false).beforePassive
    }
    #expect(!evaluate(30_000, 90, false))
    #expect(evaluate(35_000))
    #expect(!evaluate(nil))
    #expect(!evaluate(125_000))
    #expect(!evaluate(30_000, 0))
}

@Test func advanceWarningBeforeInactiveUsesCombinedBoundary() {
    var warning = AdvanceModeWarningState()
    let active: Int64 = 120_000
    let passive: Int64 = 300_000
    func evaluate(_ idle: Int64) -> Bool {
        warning.evaluate(idleMS: idle, activeMS: active, passiveMS: passive, warnBeforePassiveSeconds: 0,
            warnBeforeInactiveSeconds: 60, passiveEligible: false, inactiveEligible: true).beforeInactive
    }
    #expect(!evaluate(359_999))
    #expect(evaluate(360_000))
    #expect(!evaluate(420_000))
    #expect(!evaluate(0))
    #expect(evaluate(360_000))
}

@Test func activityTransitionNotifierDetectsPassiveAndInactiveEdges() {
    var notifier = ActivityTransitionNotifier()
    func edge(_ state: ActivityState, _ eligible: Bool = true) -> ActivityTransitionNotifier.Transition? {
        notifier.evaluate(current: state, eligible: eligible)
    }
    #expect(edge(.unknown) == nil)
    #expect(edge(.active) == nil)
    #expect(edge(.passive) == .enteredPassive)
    #expect(edge(.passive) == nil)
    #expect(edge(.inactive) == .enteredInactive)
    #expect(edge(.inactive) == nil)
    #expect(edge(.active) == nil)
    #expect(edge(.passive) == .enteredPassive)
    #expect(edge(.unknown, false) == nil)
    #expect(edge(.passive) == nil)
}

@Test func legacySettingsDefaultActivityTransitionWarningsOff() throws {
    let settings = AppSettings()
    #expect(!settings.warnWhenEnteringPassive)
    #expect(!settings.warnWhenEnteringInactive)
    let data = try JSONEncoder().encode(settings)
    let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
    #expect(!decoded.warnWhenEnteringPassive)
    #expect(!decoded.warnWhenEnteringInactive)
}

@Test func legacySettingsDefaultWarningAndShorterActiveThreshold() throws {
    var settings = AppSettings()
    #expect(settings.effectiveWarnBeforePassiveSeconds == 30)
    #expect(settings.effectiveWarnBeforeInactiveSeconds == 0)
    let data = try JSONEncoder().encode(settings)
    #expect(try JSONDecoder().decode(AppSettings.self, from: data).effectiveWarnBeforePassiveSeconds == 30)
    settings.activeMinutes = 1
    #expect(settings.effectiveWarnBeforePassiveSeconds == 5)
    settings.idleWarningAfterSeconds = 0
    #expect(settings.effectiveWarnBeforePassiveSeconds == 0)
    settings.warnBeforeInactiveSeconds = 120
    settings.passiveMinutes = 5
    #expect(settings.effectiveWarnBeforeInactiveSeconds == 120)
}

@Test func preUpgradeSettingsDecodeWithoutNewAlertFields() throws {
    var original = AppSettings()
    original.minimumHours = 36
    original.idleWarningAfterSeconds = 90
    var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
    for key in ["warnBeforePassiveSeconds", "warnBeforeInactiveSeconds", "warnWhenEnteringPassive", "warnWhenEnteringInactive"] {
        json.removeValue(forKey: key)
    }
    let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONSerialization.data(withJSONObject: json))
    #expect(decoded.minimumHours == 36)
    #expect(!decoded.warnWhenEnteringPassive)
    #expect(!decoded.warnWhenEnteringInactive)
    #expect(decoded.effectiveWarnBeforePassiveSeconds == 30)
}
