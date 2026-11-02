import Foundation
import Testing
@testable import PlatformCollectors

@Test func tracePreservesLifecycleWithoutSensitiveFieldsOrRepeatedSamples() throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appending(path: "trace.json")
    var trace = DiagnosticTrace(fileURL: url)
    func observation(_ event: String) -> DiagnosticObservation {
        .init(timestamp: Date(timeIntervalSince1970: 0), event: event, bundleID: "sensitive.example.app",
              idleMilliseconds: 123, state: .inactive, health: .continuous)
    }
    try trace.record(observation("session_inactive"))
    for _ in 0..<100 { try trace.record(observation("sample")) }
    try trace.record(observation("display_sleep"))
    let data = try Data(contentsOf: url)
    let rows = try #require(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
    #expect(rows.count == 2)
    #expect(rows[0]["event"] as? String == "session_inactive")
    #expect(rows[1]["event"] as? String == "display_sleep")
    #expect(Set(rows[0].keys) == ["timestamp", "event", "activity", "health"])
    #expect(!String(decoding: data, as: UTF8.self).contains("sensitive.example.app"))
    let permissions = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
    #expect(permissions?.intValue == 0o600)
}

@Test func traceIsBoundedAndNewSessionReplacesOldEvidence() throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appending(path: "trace.json")
    var trace = DiagnosticTrace(fileURL: url)
    for i in 0..<260 {
        try trace.record(.init(timestamp: Date(timeIntervalSince1970: Double(i)), event: "sleep",
                               bundleID: nil, idleMilliseconds: nil, state: .inactive, health: .continuous))
    }
    let rows = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [[String: Any]])
    #expect(rows.count == 256)
    var replacement = DiagnosticTrace(fileURL: url)
    try replacement.record(.init(timestamp: Date(), event: "started", bundleID: nil,
                                 idleMilliseconds: nil, state: .unknown, health: .initial))
    let newRows = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [[String: Any]])
    #expect(newRows.count == 1)
}

@Test func traceWriteFailureIsReported() throws {
    let file = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: file) }
    try Data().write(to: file)
    var trace = DiagnosticTrace(fileURL: file.appending(path: "not-a-directory.json"))
    #expect(throws: (any Error).self) {
        try trace.record(.init(timestamp: Date(), event: "started", bundleID: nil,
                               idleMilliseconds: nil, state: .unknown, health: .initial))
    }
}
