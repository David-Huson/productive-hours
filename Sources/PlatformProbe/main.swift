import Foundation
import PlatformCollectors

// A deliberate single observation. Prints availability, never the application identifier.
@main
struct PlatformProbe {
    @MainActor static func main() {
        let collector = PlatformCollector()
        collector.onObservation = { observation in
            print("foreground_available=\(observation.bundleID != nil)")
            print("idle_ms=\(observation.idleMilliseconds.map(String.init) ?? "unavailable")")
            print("activity=\(observation.state.rawValue)")
            print("lock_detection=unverified")
            print("permission_prompt_requested=false")
        }
        collector.sample(event: "single_probe")
    }
}
