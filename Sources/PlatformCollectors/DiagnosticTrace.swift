import Foundation

/// Bounded Phase 0 evidence, deliberately excluding app identities and input payloads.
public struct DiagnosticTrace {
    public struct Entry: Codable, Equatable {
        public let timestamp: Date
        public let event: String
        public let activity: String
        public let health: String
    }

    private let fileURL: URL
    private var entries: [Entry] = []
    private var previousState: String?
    private var previousHealth: String?
    private static let limit = 256

    public init(fileURL: URL) { self.fileURL = fileURL }

    public mutating func record(_ observation: DiagnosticObservation) throws {
        let state = observation.state.rawValue
        let health = observation.health.rawValue
        let lifecycle = ["started", "stopped", "sleep", "wake", "display_sleep", "display_wake", "session_inactive", "session_active"]
        guard lifecycle.contains(observation.event) || state != previousState || health != previousHealth else { return }
        let entry = Entry(timestamp: observation.timestamp,
                          event: lifecycle.contains(observation.event) ? observation.event : "state_changed",
                          activity: state, health: health)
        let proposed = Array((entries + [entry]).suffix(Self.limit))
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(proposed)
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        // Set directory permissions before the atomic writer creates its temporary file.
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        try data.write(to: fileURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        entries = proposed
        previousState = state
        previousHealth = health
    }
}
