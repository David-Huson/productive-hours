import Foundation
import Testing
@testable import ActivityCore

@Test func idleWarningFiresOnceAndRearmsAfterInput() {
    var warning = IdleWarningState()
    func evaluate(_ idle: Int64) -> Bool { warning.evaluate(idleMS: idle, warningSeconds: 90, activeMinutes: 2, eligible: true) }
    #expect(!evaluate(89_999))
    #expect(evaluate(90_000))
    #expect(!evaluate(95_000))
    #expect(!evaluate(120_000))
    #expect(!evaluate(0))
    #expect(evaluate(90_000))
}

@Test func idleWarningSkipsSuppressedUnknownDisabledAndLateSamples() {
    var warning = IdleWarningState()
    func evaluate(_ idle: Int64?, _ seconds: Int = 90, _ eligible: Bool = true) -> Bool {
        warning.evaluate(idleMS: idle, warningSeconds: seconds, activeMinutes: 2, eligible: eligible)
    }
    #expect(!evaluate(90_000, 90, false))
    #expect(evaluate(95_000))
    #expect(!evaluate(nil))
    #expect(!evaluate(125_000))
    #expect(!evaluate(90_000, 0))
}

@Test func legacySettingsDefaultWarningAndShorterActiveThreshold() throws {
    var settings = AppSettings()
    #expect(settings.effectiveIdleWarningSeconds == 90)
    let data = try JSONEncoder().encode(settings)
    #expect(try JSONDecoder().decode(AppSettings.self, from: data).effectiveIdleWarningSeconds == 90)
    settings.activeMinutes = 1
    #expect(settings.effectiveIdleWarningSeconds == 55)
    settings.idleWarningAfterSeconds = 0
    #expect(settings.effectiveIdleWarningSeconds == 0)
}
