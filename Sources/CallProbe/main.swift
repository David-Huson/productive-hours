import Foundation
import PlatformCollectors

// Run once by default, or --watch for a bounded 20-minute diagnostic session.
// Redirect output to a private file when testing. No participant names or audio.
let watch = CommandLine.arguments.contains("--watch")
let formatter = ISO8601DateFormatter()
for _ in 0..<(watch ? 600 : 1) {
    let now = formatter.string(from: Date())
    do {
        let samples = try CallAudioProbe.sample()
        let flags = samples.map { "\($0.app):input=\($0.input),output=\($0.output)" }.joined(separator: " ")
        print("\(now) \(flags.isEmpty ? "no_target_audio_process" : flags)")
    } catch {
        print("\(now) unavailable code=\((error as NSError).code)")
    }
    fflush(stdout)
    if watch { Thread.sleep(forTimeInterval: 2) }
}
