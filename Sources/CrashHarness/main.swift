import Foundation
import Darwin
import ActivityCore
import Persistence

// Process-level durability fixture. Never opens the user's application database.
guard CommandLine.arguments.count == 3 else { fatalError("Usage: CrashHarness committed|uncommitted|verify /temporary/database.sqlite") }
let mode = CommandLine.arguments[1]
let url = URL(fileURLWithPath: CommandLine.arguments[2])
let store = try Store(url: url)
if mode == "verify" {
    var engine = try store.load("checkpoint", as: TrackingEngine.self)!
    guard engine.boundary == 30_000 else { fatalError("Checkpoint mismatch") }
    let gap = engine.recover(at: 2_730_000)
    try store.commit(gap, checkpoint: engine)
    let rows = try store.intervals()
    guard rows.filter(\.productive).reduce(0, { $0 + $1.seconds }) == 30,
          rows.filter({ $0.activity == .unknown }).reduce(0, { $0 + $1.seconds }) == 2700,
          zip(rows, rows.dropFirst()).allSatisfy({ $0.end == $1.start }) else { fatalError("Recovery accounting mismatch") }
    print("PASS: abrupt-exit recovery preserves 30 seconds and marks 45-minute downtime unknown")
} else {
    var engine = TrackingEngine(start: 0)
    _ = engine.apply(.pause(false), at: 0)
    _ = engine.apply(.recovered, at: 0)
    _ = engine.apply(.input, at: 0)
    _ = engine.apply(.foreground(Source(app: "fixture", productivity: .productive)), at: 0)
    let rows = engine.apply(.tick, at: 30_000)
    try store.commit(rows, checkpoint: engine)
    if mode == "uncommitted" { _ = engine.apply(.tick, at: 60_000) }
    else if mode != "committed" { fatalError("Unknown mode") }
    // No Swift destructors or SQLite close/checkpoint run on this path.
    _exit(77)
}
