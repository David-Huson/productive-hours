# Implementation plan and acceptance gates

Implementation has progressed beyond the original spike. See [current implementation status](implementation-status.md) for delivered features and outstanding verification; the table below records the original milestone sequence.

Read the complete [PRD](Productive-Hours-PRD.md), version 1.0, before changing scope. This plan follows its phase order. Phase 4 is outside V1.

| Milestone | Deliverable | Required evidence | Status |
|---|---|---|---|
| 0.1 | Swift package, native menu-bar diagnostic, public foreground/idle/lifecycle observers | Compile all targets; real availability probe; threshold and clock tests | Implemented; see validation record |
| 0.2 | Target-machine event trace and permission matrix | App switches, 2m idle, lock, sleep/wake; denied/revoked permissions; no undocumented APIs | Open |
| 0.3 | Compare native browser capture with Chrome extension/IPC and update ADR | Active-tab fidelity, private-mode exclusion, minimal permissions; permitted installation/authenticated IPC if extension chosen | Open; user reports extension-free ActivTrak capture; policy unknown |
| 1.1 | Pure typed event reducer and fake-clock fixtures | FR-03/06; nine-minute idle, passive app switch, nested barriers, duplicates, out-of-order events, clock jumps, no overlap | Pending Phase 0 |
| 1.2 | SQLite migrations, transactional ledger/checkpoint | FR-06/10; crash after each commit stage; 45m restart gap; reopen exact totals; failure paths; file permissions | Pending |
| 1.3 | App classification and calendar accounting | FR-05/07; undefined default, version provenance; Sunday rollover; DST both directions; timezone change; budget examples | Pending |
| 1.4 | Consent onboarding, native settings and menu-bar metrics | FR-01/02; 10m three-app sequence; visible updates within 60s; pause as unknown; relaunch accurate totals | Pending |
| 2.1 | Chrome MV3 hostname adapter and domain rules | FR-04/05; active foreground tab only; no incognito; disconnect/stale/replay handling; exclusion precedence | Pending |
| 2.2 | Forecast, history and Undefined queue | FR-07/09; partial workday; zero remaining capacity; <3 days low confidence; unknown/ignored denominator cases | Pending |
| 2.3 | Alerts and full-day integration | FR-08; 30m sustained condition; daily cooldown, quiet hours, snooze; denied notification permission; 8h controlled run | Pending |
| 3.1 | Calibration, history preview and data controls | FR-09/10; five-day sample; immutable corrections; reversible rule edits; aggregate export; retention; complete deletion | Pending |
| 3.2 | Release hardening and distribution | NFR-01–10; CPU/RSS/startup measurements; no outbound telemetry; keyboard/VoiceOver; signed/notarized artifact; full week acceptance | Pending |

## Testing discipline

Every implementation milestone includes automated tests alongside behavior. Use Swift Testing for deterministic core fixtures and real temporary SQLite databases for integration. Add process-level crash tests for durability. Never claim a fake-clock test verifies an OS notification or permission.

Test accounting with generated event streams in addition to examples: positive durations, one category per elapsed span, no overlaps, sum of all categories bounded by observed elapsed time, replay/restart stability. Keep fixed seeds and fixture inputs in source control. Include full Monday–Sunday fixtures, DST changes, long idle, threshold customization, app/browser events while passive and missing coverage.

Coverage is measured, not substituted for acceptance. Require branch cases for reducer transitions, rule precedence, calendar slicing and recovery. UI tests cover consent/status and keyboard access after full Xcode is available. Run minimum supported macOS and current target OS before release; this Mac alone cannot validate macOS 14 or Intel support.

## Main risks

| Risk | Consequence | Gate/response |
|---|---|---|
| No verified public lock event | False credit during locked screen | Block productive tracking until resolved |
| Idle API permissions or synthetic-event semantics vary | Incorrect presence inference | Clean-account and denial/revocation matrix; label estimates; never generate input |
| Collector queue delayed or wall clock changes | Wrong attribution/negative intervals | Monotonic checks, explicit gaps, event-order tests |
| SQLite partial writes/crash | Lost or duplicate credit | One transaction plus checkpoint; injected crash tests |
| Browser policy blocks extension | No domain coverage | Visible undefined fallback; no bypass |
| Native host origin spoofing | Untrusted attribution | Validate IPC/authentication and scope local threat model |
| Retention removes raw rows | Historical rebuild impossible | Preserve summary totals and explain recalculation limits |
| Only command-line tools installed | UI testing/signing workflow incomplete | Package tests now; full Xcode and Developer ID release setup later |

## Meeting requirement refinement

See [ADR 0002](adr/0002-passive-productivity-and-meetings.md). The user expects productive calls to remain distinguishable from unattended idle. Independent activity/productivity types and credit eligibility tests are implemented early; observations remain Undefined until rules exist. Add verified call-state feasibility to Phase 0 and meeting-policy fixtures to milestone 1.1 before enabling any exception to the seven-minute cutoff. Automatic meeting detection and manual meeting time must remain distinguishable.

## Metrics interface refinement

Follow [ADR 0003](adr/0003-metrics-interface.md): a compact menu-bar pace/status view and brief actionable popover, with detailed totals, breakdowns and history in a native dashboard. This supersedes the dense PRD popover layout. Milestone 1.4 supplies actual totals in the dashboard; milestone 2.2 supplies validated forecasts/trends. Until then, communicate calibration/coverage honestly rather than displaying invented pace.
