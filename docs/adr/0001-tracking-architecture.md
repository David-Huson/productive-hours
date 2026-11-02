# ADR 0001: Accounting ownership and platform boundaries

Status: accepted for implementation; platform feasibility remains open.

## Contract

The eventual application submits typed, timestamped events to one `TrackingCoordinator` actor. It receives a committed metrics snapshot or an explicit storage/collection failure. SwiftUI does not advance clocks or write intervals.

```swift
let snapshot = try await coordinator.process(event)
```

The coordinator asks a pure reducer for a proposed next state and completed intervals. A SQLite transaction inserts the accepted event, intervals, and checkpoint. Only after commit does the coordinator publish the new state. Failed commits stop credit and expose a gap. The Phase 0 package currently implements diagnostic observations and timing primitives, not this production contract.

## Ownership and types

- `ActivityCore`: deterministic reducer, integer-millisecond intervals, timing policy, classification, calendar slicing and metrics. No AppKit or database imports.
- `PlatformCollectors`: AppKit/Quartz observations with wall and monotonic clocks. Normalize observations into events, never calculate totals here.
- `Persistence`, Phase 1: one SQLite writer, versioned migrations, transaction and recovery ownership. Prefer GRDB after dependency/version review. No ORM-managed implicit saves.
- `ProductiveHours`: SwiftUI menu bar, consent and status, then native settings/history. Owns lifecycle, not accounting.
- Browser adapter, Phase 2: enriches the current foreground source. Never owns a timer or writes ledger rows.

Production types will distinguish `EventID`, UTC epoch milliseconds, monotonic milliseconds, app bundle ID, normalized hostname, rule version, productivity class and activity state. Unknown/paused and inactive remain separate. Lock, sleep and session inactivity are independent barriers, so waking a display cannot clear a system-sleep barrier.

## Accounting rules

Use half-open intervals. Advance through exact 120-second and 420-second boundaries even when the timer fires late. Input observation is the only event that resets last input. Foreground or browser changes cannot imply input. Reject duplicate and out-of-order events. Late observations cannot rewrite committed history silently.

After resume, require fresh observation; never infer that unlocking means productive work. Startup restores the last durable checkpoint and inserts unknown downtime before accepting fresh observations. A checkpoint every 30 seconds bounds crash loss; normal five-second observation does not require five-second writes. Persist transitions and bounded checkpoints atomically.

Detect wall/monotonic divergence. Do not subtract wall timestamps blindly after clock changes. Quarantine the affected span and re-anchor observation without overlapping committed UTC intervals. Backward-clock handling must be fixture-tested before credit resumes. The Phase 0 diagnostic only flags anomalies, and is not a production recovery implementation.

Split UTC intervals using Calendar and the chosen IANA timezone, including week/day/DST boundaries. Preserve elapsed milliseconds; round only for display. Rebuildable summaries are caches. Manual/reference totals are separate ledgers.

## Persistence integrity, Phase 1 gate

SQLite WAL, foreign keys, explicit migrations and bound parameters. Tables follow PRD section 9, plus a checkpoint and migration version. Require positive duration, unique event ID, rule provenance and an overlap rejection check/trigger within the writer transaction. Store UTC milliseconds as Int64. Durable synchronous commits must be tested, not inferred from WAL alone.

Test process termination before/after each transaction stage; reopen the database and prove idempotent recovery. Test read-only/disk-full/corrupt storage paths. Never replace a corrupt database silently. App support directory mode 0700, data files 0600; inspect WAL/SHM permissions too. Retention must preserve summaries before deleting raw data, and explain limits on historical recalculation.

## Alternatives considered

1. UI-owned timer with periodic total saves: fewer initial types, but couples credit to UI scheduling and cannot reconstruct crash boundaries. Rejected.
2. Append-only event sourcing with full replay: strong audit history, but retains more diagnostics and complicates 14-day event/90-day interval retention. Rejected for V1.
3. Pure reducer plus transactional interval ledger/checkpoint: chosen. Supports bounded recovery and deterministic fixtures without keeping every sample.

## Platform and distribution

macOS 14+ baseline, Swift 6 language mode, SwiftUI `MenuBarExtra`, AppKit `NSWorkspace`. Initial distribution is a Developer ID signed, hardened-runtime, notarized app outside the Mac App Store. No root or daemon. The spike bundle uses ad-hoc signing for local execution only and is not a release artifact. App Sandbox remains disabled pending Native Messaging validation; sandbox disablement is not permission approval.

Quartz aggregate input-idle query reads elapsed time only. No event tap, key code, text, cursor path, window title, Screen Recording request or Accessibility request. API success on this Mac does not establish permission behavior on a clean account or minimum supported OS.

`NSWorkspace` session notifications document user-session switching, not a guaranteed lock event. Display sleep is also not equivalent to lock. Do not use undocumented `com.apple.screenIsLocked` dictionary keys or distributed notification names to conceal this gap. Reliable public lock observation is a Phase 0 blocker. If no acceptable public mechanism exists, record a product decision with the user before changing the requirement.

## Browser boundary

Chrome Native Messaging uses stdio and a per-user host manifest, no TCP listener. Exact extension origin, fixed command schema, small frame limit, replay IDs and timestamp windows are necessary. The browser's allowlist and argv origin are not sufficient authentication against arbitrary local processes. Validate a signed host/app IPC design and explicitly document the same-user threat boundary before collecting domains. Do not claim an absolute defense against a compromised user account.

Policy is unknown on the intended target Mac, per user response. Do not install an extension or change managed policies as a feasibility shortcut. A blocked extension must leave browser activity undefined unless the user supplies an explicit app fallback rule.

## Sources checked

- [Apple aggregate idle API](https://developer.apple.com/documentation/coregraphics/cgeventsource/secondssincelasteventtype(_:eventtype:)) and installed SDK `CGEventSource.h`, aggregate query uses `kCGAnyInputEventType`.
- [Apple session resignation](https://developer.apple.com/documentation/appkit/nsworkspace/sessiondidresignactivenotification), explicitly describes session switching.
- [Apple display sleep](https://developer.apple.com/documentation/appkit/nsworkspace/screensdidsleepnotification).
- [Chrome Native Messaging](https://developer.chrome.com/docs/extensions/develop/concepts/native-messaging), framing, host registration and allowed origins.
- [Chromium security FAQ](https://chromium.googlesource.com/chromium/src/+/main/extensions/docs/security_faq.md), Native Messaging is not itself a secure channel.

## Browser discovery update from user feedback

The user reports ActivTrak captures URLs without a Chrome extension. Official ActivTrak documentation confirms its desktop agent captures URL data independently; Assist extends coverage. The reviewed documentation does not establish the internal capture mechanism. Do not claim it uses DNS or Accessibility without evidence.

Reopen the browser-adapter choice for Phase 0: compare a narrowly scoped, consented native browser API/Accessibility approach with the PRD's extension approach before committing. Require active-tab attribution, reliable private-mode exclusion, no titles/content collection, prompt hostname reduction, visible failure, and public APIs. Reading an entire accessibility tree would violate the intended minimization boundary; do not use that as a shortcut. No new browser permissions or collection are enabled by this decision.

DNS alone is unsuitable as the accounting source: it cannot identify a full URL or prove which tab is foreground, and cached/prefetched/background lookups do not correspond one-to-one with active navigation. Native browser capture is a feasibility candidate, not a verified capability. Preserve FR-04's original extension requirement in the source PRD; record any implementation change explicitly after validation.

Reference: [Understanding the ActivTrak Agent](https://support.activtrak.com/hc/en-us/articles/360060260991-Understanding-the-ActivTrak-Agent), desktop agent versus optional Assist extension.
