# Worktempo

Native macOS menu-bar app for estimated productive digital time. Swift 6, SwiftUI, public AppKit/Quartz observers, and local SQLite. macOS 14+; no third-party runtime dependencies.

## Build and run

```sh
./scripts/verify.sh
open '.build/verification/Worktempo.app'
```

The built app starts with tracking disabled on first launch. Open the dashboard, review Settings and enable tracking. Classify observed apps from the Undefined queue. Unknown apps and browser domains do not count as productive automatically.

The menu bar shows pace or a tracking issue. The dashboard contains weekly targets, productive Active/Passive totals, daily history, tracking gaps, projections, classifications, reference comparisons and privacy controls.

## Behavior

- Default target: 35–40h; Monday week start; Mon–Fri 09:00–17:00 in your chosen IANA timezone.
- Recent input: Active for 2 minutes, then Passive for 5 additional minutes. Beyond 7 minutes: Inactive. Only Productive + Active/Passive contributes to automatic totals.
- App switches and browser changes never manufacture input.
- State transitions and bounded 30-second checkpoints commit with intervals in one SQLite transaction. A restart leaves uncommitted downtime Unknown.
- Lock/session/display-sleep signals stop credit conservatively. Exact screen-lock coverage on this Mac is still a manual verification item; display sleep is not proof of lock detection.
- Forecast needs three usable scheduled days, uses up to 28 days with recency weighting, and excludes already elapsed schedule capacity. Low confidence is explicit.
- A timed work meeting is a user declaration, stored separately from automatic time. It can overlap the automatic estimate and is never silently added. Zoom/Discord audio activity now contributes to automatic time; Teams remains manual.

## Browser support

Enable browser observation in Settings, then save. Chrome, Edge and Arc use their public AppleScript interface, requiring your macOS Automation consent. The adapter checks foreground and private-window mode before requesting the active-tab URL, immediately reduces a transient URL to its hostname, and never logs or stores a full URL. No browser extension, content script, network listener, navigation or history scraping is used.

Unsupported browsers, denied permissions and unavailable websites have no domain attribution. Explicit app-level fallback rules are allowed. Private windows detected by supported adapters are Ignored. No policy bypass is attempted. Arc, Safari and Firefox domain support is not included in this version.

This intentionally revises the PRD's extension-first transport after the user's feedback. The required hostname-only, foreground-only and visible-degradation behavior is preserved; real browser permission/privacy tests remain pending.

## Local data

`~/Library/Application Support/ProductiveHours/activity.sqlite` contains the ledger, checkpoint, settings, rules/revisions, summaries, references and manual work. SQLite WAL, FULL synchronization, overlap constraints and owner-only directory/file permissions protect the local write path. No analytics, sync or error-reporting service is configured.

Detailed intervals default to 90-day retention. Expired intervals become day summaries, retained for 365 days. Those summaries cannot be reclassified or regrouped into a new timezone after raw rows expire. Historical recalculation previews its productive-time change, versions the action and supports undo for retained rows.

`Diagnostics/phase-0.json` contains at most 256 state/lifecycle changes, with timestamps and status only. It contains no app identifiers, domains, input payloads or content. A new process replaces the diagnostic snapshot on its first recorded observation. Repeated unchanged samples do not write.

Delete all local data requires confirmation in Settings, stops tracking, removes the ledger contents, rules, references, summaries, manual work and diagnostics, and truncates database journals. Aggregated CSV export contains day totals, not app/domain detail.

## Calibration

Select the reference timezone and metric explicitly. Manual corrections append a reference record linked to the prior value. Import accepts UTF-8 CSV with `date,productive_seconds` headers; dates are `YYYY-MM-DD` and totals are seconds. Extra columns are discarded. Other ActivTrak export schemas must first be mapped to this explicit schema. No employer credentials are requested.

Comparison shows daily deltas, selected-week discrepancy/percentage and median daily absolute error. Unknown employer settings, other devices, browser gaps and different idle rules can explain differences.

## Verification and distribution

`./scripts/verify.sh` runs all automated tests and builds a locally ad-hoc-signed application with hardened runtime and the Apple Events entitlement. It does not exercise the user's desktop or grant permissions. The cache wrapper works around this machine's command-line-toolchain plugin/cache paths.

To produce a Developer ID signed/notarized archive after verification:

```sh
DEVELOPER_ID='Developer ID Application: Your Name (TEAMID)' \
NOTARY_PROFILE='your-keychain-profile' ./scripts/release.sh
```

Signing credentials are not bundled. No notarization submission has been made. Device-specific verification notes are retained locally in `docs/implementation-status.md` and `docs/phase-0-validation.md`, which are excluded from Git.

## Automatic Zoom and Discord calls

While tracking runs, Zoom or Discord audio input or output activity counts as productive time, including muted calls and listening without typing. The app reads audio-usage flags, not audio content. Call time appears in the existing active/passive totals, counted once, attributed to the call app. The menu shows “Work call counted” when applicable.

Pause, observed sleep/lock, ignored apps and known private windows block credit. Call evidence expires after ten seconds without a refresh. Call detection is an audio-activity heuristic and can include app audio outside a call. Other meeting apps still require the separate manual timer.

## App identity

Worktempo is the new display name for Productive Hours. The bundle identifier, executable and existing `ProductiveHours` data folder intentionally stay unchanged, preserving settings, local history and launch-at-login identity. `Resources/Worktempo.png` is the original logo artwork. `scripts/build-icon.sh` generates all standard macOS icon sizes into the build directory; app packaging includes the resulting ICNS.

## Schedule pace and forecast

Main status compares logged productive time with your configured target range multiplied by the fraction of this week's scheduled work hours already elapsed. It works on day one, uses your reporting timezone and workdays, and does not assume missing hours were productive. A one-minute tolerance absorbs checkpoint latency; menu pace transitions retain their five-minute stabilization.

The weekly forecast remains separate and needs three usable days. The dashboard displays expected-by-now versus logged time even while that forecast calibrates.

The overview burnup chart plots daily cumulative productive time, a dashed pace line toward the upper target, and the weekly target band. The pace line advances during configured working hours and stays flat outside them. Future actual points are omitted.
