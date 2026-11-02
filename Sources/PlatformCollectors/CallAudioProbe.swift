import Foundation
import CoreAudio
import ActivityCore

/// Audio IO is a call heuristic, not proof of meeting participation.
/// Reads flags, never samples audio or creates an audio tap.
public struct CallAudioSignal: Codable, Sendable {
    public var app: String
    public var input: Bool
    public var output: Bool
    public init(app: String, input: Bool, output: Bool) {
        self.app = app; self.input = input; self.output = output
    }
}

public enum CallAudioProbe {
    /// Muting must not end credit while output remains active. Stable ordering avoids
    /// counting concurrent calls twice. Explicit app exclusions take precedence.
    public static func productiveSource(_ signals: [CallAudioSignal], rules: [ClassificationRule]) -> Source? {
        for signal in signals.sorted(by: { $0.app < $1.app }) where signal.input || signal.output {
            let bundle: String
            switch signal.app {
            case "Zoom": bundle = "us.zoom.xos"
            case "Discord": bundle = "com.hnc.Discord"
            default: continue
            }
            let classification = RuleEvaluator.resolve(app: bundle, host: nil, rules: rules)
            guard classification.productivity != .ignored else { continue }
            return Source(app: bundle, productivity: .productive)
        }
        return nil
    }
    static func callApp(_ bundle: String) -> String? {
        for (prefix, name) in [("us.zoom.xos", "Zoom"), ("us.zoom.CptHost", "Zoom"), ("com.hnc.Discord", "Discord")] {
            if bundle == prefix || bundle.hasPrefix(prefix + ".") { return name }
        }
        return nil
    }

    public static func sample() throws -> [CallAudioSignal] {
        var address = property(kAudioHardwarePropertyProcessObjectList)
        var size: UInt32 = 0
        try check(AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size))
        var objects = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        if size > 0 {
            try objects.withUnsafeMutableBytes { bytes in
                try check(AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, bytes.baseAddress!))
            }
        }
        var signals: [String: CallAudioSignal] = [:]
        for object in objects {
            var bundle: Unmanaged<CFString>?
            var bundleSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            var bundleAddress = property(kAudioProcessPropertyBundleID)
            try check(AudioObjectGetPropertyData(object, &bundleAddress, 0, nil, &bundleSize, &bundle))
            guard let bundle else { continue }
            let identifier = bundle.takeRetainedValue() as String
            guard let app = callApp(identifier) else { continue }
            let input = try flag(object, kAudioProcessPropertyIsRunningInput)
            let output = try flag(object, kAudioProcessPropertyIsRunningOutput)
            let old = signals[app]
            signals[app] = CallAudioSignal(app: app, input: input || old?.input == true, output: output || old?.output == true)
        }
        return signals.values.sorted { $0.app < $1.app }
    }

    private static func property(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }
    private static func flag(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) throws -> Bool {
        var address = property(selector)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        try check(AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value))
        return value != 0
    }
    private static func check(_ status: OSStatus) throws {
        guard status == noErr else { throw NSError(domain: "CallAudioProbe", code: Int(status)) }
    }
}
