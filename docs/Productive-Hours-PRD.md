# Productive Hours — Product Requirements Document

**Version:** 1.0 (implementation-ready draft)  
**Date:** October 30, 2026  
**Platform:** macOS (native menu-bar application)  
**Target user:** One person tracking their own work activity  
**Default weekly target:** 35–40 hours of estimated productive time  
**Status:** Ready for engineering discovery and phased implementation

## 1. Executive summary

Productive Hours is a local-first macOS application that estimates productive computer time using a model comparable to ActivTrak's reported **Productive** metric. It runs unobtrusively in the menu bar, observes the foreground application and optionally the active browser domain, tracks keyboard/mouse *presence* (never contents), and categorizes elapsed time as Productive, Unproductive, Undefined, or Ignored. Time also has an independent activity state: Active, Passive, or Inactive.

The app answers three questions throughout the workweek:
1. **How much productive time have I accumulated this week?**
2. **Am I on pace to finish between 35 and 40 productive hours?**
3. **How much additional productive time is needed, and should I adjust my workload?**

It provides a weekly progress dashboard, forecast, clear and infrequent notifications, and a classification/calibration workflow. All tracking data remains on-device by default.

**Important limitation:** The app makes an **estimate**, not an authoritative reproduction of ActivTrak. The employer's configuration, classification rules, tracked schedule, other monitored devices, and proprietary processing may differ. The app must never claim to have read or changed ActivTrak data unless the user explicitly imports authorized report data. It must not interact with, disable, or spoof the employer's agent.

## 2. Goals and non-goals

### Goals (G)
- **G1:** Track estimated weekly Productive Time in near real time, with a default band of **35–40 hours**.
- **G2:** Model *both* Productive Active and Productive Passive intervals and never count Inactive intervals.
- **G3:** Classify desktop applications and browser domains with transparent user-configurable rules.
- **G4:** Provide actionable pacing: remaining to minimum, headroom to maximum, required average per remaining scheduled day, and projected weekly total.
- **G5:** Provide user-friendly calibration against voluntarily supplied ActivTrak exports or manually entered summary figures.
- **G6:** Operate reliably over a full workweek with small resource usage and no cloud requirement.
- **G7:** Minimize collection of sensitive data, especially healthcare-related information.

### Non-goals (NG)
- **NG1:** No automation or simulation of keyboard/mouse activity; no manipulation, evasion, or interference with ActivTrak.
- **NG2:** No keystroke logging, screen capture, clipboard capture, audio/video recording, browser history harvesting, or collection of document contents.
- **NG3:** No employee/team monitoring, remote administrator, cloud dashboard, or multi-user functionality.
- **NG4:** No claim that 35–40 productive hours establishes hours worked, payroll hours, or performance. Productive digital time and actual labor are not interchangeable.
- **NG5:** No silent broad access to browser data or use of private macOS APIs.
- **NG6:** No guaranteed one-to-one matching against private employer configuration.

## 3. Product principles and assumptions

1. **Local-first and consent-based.** User explicitly enables monitoring, permissions, browser support, and launch-at-login.
2. **Observable and honest.** Show an estimated figure, data coverage status, and classification uncertainty; do not silently treat unknown activity as productive.
3. **Weekly, not daily, optimization.** Monday–Sunday is the default week; Monday–Friday are the default planned workdays. Both are configurable.
4. **Configurable limits.** Minimum 35 h and maximum 40 h per week; users can change both and notification thresholds.
5. **Separate ledgers.** Automatically observed productive digital time is the primary metric. User-entered offline work/meetings are shown separately and never silently merged into the ActivTrak-like metric.
6. **Respect employer policy.** The app runs only on devices where the user may install it and access the necessary information.
7. **Fail visibly.** When permissions, browser coverage, or collection fail, indicate a tracking gap instead of pretending the time was zero or productive.

## 4. Definitions and measurement model

**Productivity class:** `productive | unproductive | undefined | ignored`. Classification is assigned to a foreground app or active browser domain, based on rules and priority.

**Activity state:**
- `active`: recent real input; additionally includes the configurable initial grace period after the last input.
- `passive`: a configurable subsequent no-input interval, attributed to the last observed activity's classification.
- `inactive`: no-input interval beyond the passive stop limit, or screen locked/asleep. Count no productive time.
- `unknown`: collector unavailable, permissions missing, clock anomaly, or an unresolvable gap. Do not assume this is inactive or productive.

**Default timing profile (user-configurable):**
- Passive starts **2 minutes after last user input**.
- Passive is collected for **up to 5 additional minutes** (i.e., until 7 minutes since last input). **Five minutes is a proposed default for this app**, not a claim about an employer's settings.
- After that, the interval becomes Inactive until genuine user input resumes.
- Treat an app switch or browser navigation as a classification change only when supported by a trustworthy activity/foreground event; do not use it to fabricate input.
- Lock and sleep terminate credited intervals immediately, regardless of configured thresholds.

**Example:** If a productive app remains foreground and no input occurs for 9 minutes: 0–2 minutes count as Productive Active; 2–7 minutes count as Productive Passive; 7–9 minutes count as Inactive. Total credited = 7 minutes. Recalculate only from observed event time, never from assumed presence.

**Primary metric:**
`estimated_productive_seconds = productive_active_seconds + productive_passive_seconds`.

**Other metrics:** `productive_active`, `productive_passive`, `unproductive`, `undefined`, `ignored`, `inactive`, `unknown_gap`, `observed_screen_time`, and optional `manual_offline_work`. Show Active/Passive sub-breakdowns and never double count an elapsed second. Ignored time is excluded from eligible denominators; Unknown time is always distinguished from zero activity.

**Calendar boundary:** Store UTC event timestamps; calculate weeks and days in the user's chosen IANA timezone. Split intervals exactly at week boundaries and daylight-saving transitions. Use half-open intervals `[start, end)` and elapsed time in seconds (no per-minute rounding in storage).

## 5. User journeys

### UJ-01: First launch (under five minutes of interaction)
1. User launches app and sees the purpose, privacy explanation, and policy reminder.
2. User chooses week start, timezone, planned workdays, weekly lower/upper thresholds (default 35/40), and preferred workday schedule (default Mon–Fri, 9:00–17:00, adjustable).
3. App requests only permissions strictly needed by enabled features, with a clear explanation and a fallback path.
4. User enables foreground-app monitoring, sets initial app classifications, and optionally installs a supported browser extension.
5. User chooses whether to enable macOS notifications and launch-at-login.
6. App starts recording; the menu bar displays `0h 00m / 35–40h` and a `Calibrating`/`Limited coverage` indicator as appropriate.

### UJ-02: Normal workday
1. User codes in an IDE, switches to Slack, and reviews documentation in the browser.
2. The app records non-overlapping intervals with a productivity class and activity state.
3. The menu-bar popover updates at least once per minute without requiring refresh.
4. User sees accumulated Productive Time, remaining to 35 hours, headroom to 40, and a projection for the end of the week.

### UJ-03: Pacing notification
1. A sustained projection indicates finishing below 35 hours or above 40 hours.
2. App sends a single contextual notification, subject to cooldown and quiet-hours rules.
3. User opens the dashboard to see why and can snooze that type of alert. Notifications recommend workload planning or a legitimate break, not activity spoofing.

### UJ-04: Classification correction
1. User sees `Undefined: 48 minutes` with affected apps/domains.
2. User marks a domain `Productive`, adds an optional subdomain rule, and sees *projected historical recalculation* before applying it.
3. App recomputes summaries from recorded intervals, preserves the rule version/audit record, and explains the change.

### UJ-05: ActivTrak comparison
1. User imports an authorized CSV or manually records official daily Productive totals.
2. App compares dates, metric definitions, timezone and measurement configuration.
3. App shows local estimate, imported total, absolute and percentage delta, and likely causes (unknown browser domains, timing thresholds, tracking gaps, group-specific classifications).
4. User can update classifications or settings but never edits the imported reference data in place without an explicit correction record.

## 6. Functional requirements and acceptance criteria

### FR-01: Native menu-bar experience — P0
- SwiftUI `MenuBarExtra` provides a compact, unobtrusive interface.
- Menu bar displays weekly productive hours (hours/minutes) and a status symbol; optional compact mode icon-only.
- Popover shows current tracking state, weekly progress, minimum remaining, maximum headroom, forecast, today's productive hours, and last updated.
- Settings and History open native windows. Users may pause/resume personal tracking from the popover; paused time is marked `unknown/paused`, not credited.

**Acceptance:** Updates visible within 60 seconds of an event; user can reach all core screens without opening a browser; tracking state is never concealed.

### FR-02: Foreground application observer — P0
- Observe activation and current frontmost application using public AppKit APIs (`NSWorkspace` and its activation notifications).
- Store app bundle identifier and display name, start/end timestamp, and current classification. Never store window title by default.
- Reconcile app-switch notifications with periodic foreground sampling to recover missed events.
- Detect app exit and user log-out; preserve accurate interval closure.

**Acceptance:** A 10-minute controlled sequence across three apps yields exact, contiguous, non-overlapping segments except explicitly marked gaps.

### FR-03: User input/idle observer — P0
- Use a documented macOS input-idle capability (Quartz/Core Graphics or another public OS API), subject to actual permission requirements verified during a technical spike.
- Collect only elapsed time since input or input-presence signals, never key codes, text, cursor trajectories, click targets, or event payloads.
- Evaluate active/passive/inactive transitions at least every 5 seconds when awake. Avoid 5-second database writes; only persist transitions or bounded checkpoints.
- Ensure synthetic activity is not intentionally generated by this app. Do not try to defeat synthetic-input detection of other systems.

**Acceptance:** 2-minute / 5-minute idle test credits the correct Active, Passive, and Inactive durations; locking or sleeping stops accrual immediately.

### FR-04: Browser activity adapter — P0 for one Chromium browser; P1 for Safari and additional browsers
- For Chrome (and optionally Edge), build a minimal Manifest V3 extension that emits active-tab *hostnames only* when a supported browser is foreground. No navigation history, URL path, query, fragments, titles, incognito activity, or page content.
- Prefer browser Native Messaging for locally scoped extension-to-app communication; authenticate/validate sender, extension identity, message schema, timestamps, and allowed commands. No unauthenticated network listener.
- Browser extension events enrich the foreground browser app event; they do not create independent counted time or overlap with desktop observation.
- If extension is absent or blocked by managed-browser policy, browser time is `undefined` unless the user explicitly creates an app-level fallback rule. Surface limited coverage conspicuously.
- P1: Safari Web Extension, Firefox adapter, and a browser-support matrix.

**Acceptance:** Switching between two domains assigns intervals correctly; multiple open tabs do not count simultaneously; private/incognito browsing is not collected; extension loss degrades visibly and safely.

### FR-05: Classification engine — P0
- Support exact bundle-ID app rules, exact host rules, subdomain/wildcard host rules, and explicit default `undefined`.
- Precedence: exact host > scoped subdomain rule > general domain rule > app rule > undefined. For a browser, a URL/host classification overrides the browser app rule. Users can reorder same-specificity rules explicitly.
- Persist `rule_id`, classification version, and provenance for each calculated segment.
- Include starter suggestions, but do not silently apply a broad `Productive` rule to all browsers. Examples: IDEs, Terminal, Jira/Confluence, GitHub, and work-related communication tools should be reviewed by the user; app and domain use can be mixed.
- Provide a user-facing `Undefined Activities` queue sorted by accumulated duration.
- Support `ignored` for explicitly excluded activities. Do not treat ignored as productive.
- On rule edits, recalculate prior **locally stored** segments on request, with a preview and versioned change history; make reclassification optional because ActivTrak may not retroactively apply settings changes in the same way.

**Acceptance:** Table-driven precedence tests pass; users can classify an app and domain without restarting; historical changes are deterministic and reversible.

### FR-06: State machine and accounting — P0
- Implement an explicit reducer/state machine driven by timestamped events: `foreground_changed`, `domain_changed`, `user_input_observed`, `idle_threshold_crossed`, `screen_locked`, `screen_unlocked`, `sleep`, `wake`, `session_ended`, `collector_failed`, `tracking_paused`, `tracking_resumed`.
- No two credited activity intervals may overlap. Every known event interval has exactly one productivity class and one activity state.
- A transition closes the prior interval at the event's effective timestamp and opens the next. Ignore or quarantine duplicate/out-of-order events rather than creating negative durations.
- Periodically checkpoint active state; after abnormal termination, restore the last durable boundary and mark any unresolved elapsed interval unknown until fresh observation. Never fill an entire downtime gap as Productive.
- Active/passive attribution follows the previous classified activity through the passive window; change classification only on reliable new information. Locked/sleep time is always inactive.
- Track clock wall-time and monotonic elapsed-time indicators to detect time changes and resume anomalies; clamp invalid or negative intervals and report gaps.

**Acceptance:** Synthetic event-stream tests prove `sum(productive + unproductive + undefined + ignored + inactive + unknown) <= wall-clock time` and no overlapping intervals. Exact totals are stable across restart and week rollover.

### FR-07: Weekly budget and forecasting — P0
- Default week Monday 00:00 through next Monday 00:00 in configured timezone; default planned days Mon–Fri; target minimum 35h, maximum 40h.
- Display:
  - `week_productive` = actual estimated productive seconds this week;
  - `remaining_to_min = max(0, 35h - week_productive)`;
  - `headroom_to_max = max(0, 40h - week_productive)`;
  - `required_daily_average = remaining_to_min / remaining_planned_workday_equivalents`;
  - `projected_week_end`, projection range, and confidence/coverage status.
- Use a deterministic projection model for V1: estimated remaining scheduled time multiplied by an observed productive yield (`productive / eligible scheduled observation time`), with bounded historical lookback and recency weighting. If less than three distinct usable workdays exist, label the projection `Low confidence` and show a simple even-distribution pace instead of fabricated precision.
- Never include already elapsed time in remaining scheduled capacity. Include partial current workday correctly. If remaining planned time is zero, show a final total and unmet minimum, not divide by zero.
- Separately show `productive digital` and `manual offline work` if the latter is enabled; the 35–40 target applies to productive digital by default.

**Acceptance:** For a static total of 24h30m: minimum remaining 10h30m and maximum headroom 15h30m. The calculator handles zero remaining days, target already reached, and target exceeded.

### FR-08: Notifications — P1
- Request notification authorization when the user enables alerts.
- Alert types: `behind_weekly_pace`, `projected_over_maximum`, `minimum_reached`, `maximum_reached`, `collection_stopped`, `coverage_degraded`.
- Default pace warnings evaluated at meaningful times, e.g., after planned workday end, not continuously during a focus session. Projections must remain outside the band for at least 30 minutes before a forecast alert.
- Enforce once-per-day per type cooldown, user-configurable quiet hours, and a snooze option; never repeatedly nag due to minute-by-minute forecast fluctuation.
- Notification copy must distinguish `estimated` from verified time and describe a practical response (review classifications, plan remaining work, take a legitimate break, or stop at a suitable boundary).

**Acceptance:** Repeated threshold crossings do not generate notification storms; denied permissions do not break tracking; app respects notification settings.

### FR-09: History, settings and calibration — P1
- History screen: daily/weekly productive bars, Active vs Passive, classification mix, tracking gaps, top apps/domains, and trend over previous weeks.
- Settings: timezone, week start, target range, planned workdays/hours, active/passive thresholds, classification rules, browser adapter status, privacy controls, retention, and notifications.
- Calibration: manual entry of authoritative day totals; optionally import authorized ActivTrak CSV, validating schema and avoiding persistence of unnecessary columns.
- Comparison view shows per-day and weekly `estimated vs reference` delta. Support different account vs local timezones and explicitly selected ActivTrak metric. The app must never imply it can read hidden organization settings.
- Record imported totals with `source`, import timestamp, selected metric, timezone, and date range, and keep them independent from observed data.

**Acceptance:** Imported five-day sample yields accurate per-day differences and weekly absolute/percentage deviation; invalid CSV is rejected with actionable errors; no employer credentials are required.

### FR-10: Privacy, data control, and reliability — P0
- All telemetry is stored locally. No analytics SDKs, cloud sync, third-party error reporting, or network calls in V1. Browser extension communication must remain local.
- Never record typed content, window titles, screenshot pixels, full URLs, patient identifiers, or page content. Default to domain/host only when browser tracking is enabled.
- Provide excluded domains/apps, pause, export of **aggregated** statistics, delete all data, and configurable retention.
- When monitoring is interrupted, display a coverage gap rather than a falsely low Productive Time estimate.
- Start at login only with explicit user preference. No root, kernel extension, Endpoint Security entitlement, or hidden background service is required.

**Acceptance:** Network monitoring confirms no outbound telemetry; storage review confirms no raw URLs/keystrokes/titles; `Delete all` removes local event/history/calibration data and related caches; permissions denied produce graceful degradation.

## 7. Interface specification

### 7.1 Menu-bar popover (default view)

```text
PRODUCTIVE HOURS                         [Tracking ●]
Week of Oct 26 – Nov 1

This week                 24h 30m
Target                    35h – 40h
[████████████░░░░░░░]     61% of upper bound

To minimum                10h 30m
Until maximum             15h 30m
Projected week            37h 10m  [Low/Med/High]
Required per workday      5h 15m

Today                      5h 42m
Productive Active          4h 10m
Productive Passive         1h 32m

Coverage: Good · Last update: 12s ago
[History] [Classifications] [Settings]
```

Illustrative figures only; displayed calculations must agree with one another for a real dataset. Progress bars should show both the 35h threshold and 40h cap, not merely a percentage to maximum. Use accessible colors *and* text/icons for status.

### 7.2 History window
- Week selector, totals and daily chart, Active/Passive stack, classification breakdown, unknown gap durations, and top sources.
- Click a day to view grouped intervals. Granular raw data view excludes sensitive titles/URLs.
- Clear `Estimate` labeling, calibration delta when available, and latest configuration version.

### 7.3 Classification settings
- Tabbed views `Applications`, `Websites`, `Undefined`, `Ignored`.
- Rows show identifier, classification, observed duration, and rule provenance; inline edit and bulk classify.
- On saving an edit, present `Apply forward only` (default) or `Recalculate stored history` with preview.

### 7.4 Status design
- `Tracking`: normal collection.
- `Paused`: user intentionally disabled collection.
- `Limited coverage`: browser adapter/permissions missing or partial source coverage.
- `Data gap`: collector was unavailable for known periods.
- `Calibrating`: insufficient valid history for trustworthy forecasts.

## 8. Technical architecture

**Recommended platform:** macOS 14+; Swift 6, SwiftUI + AppKit, structured concurrency; SQLite (prefer a maintained Swift SQLite layer such as GRDB) with WAL and explicit migrations. This is a proposed support baseline, not ActivTrak's own macOS support policy.

**Distribution:** Signed and notarized Developer ID app for initial private distribution; avoid Mac App Store until entitlement, sandbox, and browser native-messaging constraints are validated. No root install. The menu-bar process itself may perform collection; do not introduce a separate privileged daemon without a measured reliability need.

```text
+--------------------+    +--------------------+
| AppKit foreground  |    | Input idle + lock  |
| app observer       |    | sleep observer     |
+---------+----------+    +----------+---------+
          |                          |
          +-------------+------------+
                        v
             Event Normalizer/Queue  <--- Browser Native Messaging Adapter
                        |
                        v
               Activity State Machine
                        |
                  Classification
                        |
                 Interval Storage
                        |
         +--------------+---------------+
         |                              |
  Weekly Metrics + Forecast       History/Calibration
         |                              |
         +---------------+--------------+
                         v
               SwiftUI MenuBarExtra
                  + Notifications
```

**Suggested module boundaries:**
- `AppShell`: lifecycle, settings, menu bar, windows, permission guidance.
- `ActivityCollectors`: foreground, idle, session lock, wake/sleep, optional browser adapter.
- `EventNormalizer`: typed events, timestamps, deduplication, source health.
- `ActivityEngine`: pure deterministic state machine and interval generation.
- `ClassificationEngine`: rule matching, provenance, preview/recalculation.
- `Persistence`: SQLite schema, transactions, migrations, retention, export.
- `MetricsEngine`: daily/weekly aggregations, pacing, forecast, coverage.
- `NotificationEngine`: threshold logic, cooldown and quiet hours.
- `Calibration`: CSV import/manual baseline, differences and diagnostics.

**Engineering constraints:** UI must not own timing state; interval/accounting functions should be independent of AppKit and testable with a fake clock. Use serial event processing (actor/queue) so simultaneous app and browser events cannot double credit time. Browser extension must not be authoritative for elapsed duration.

## 9. Proposed persistent data model

Use SQLite with integer epoch-millisecond timestamps for persistence and integer elapsed milliseconds/seconds for accounting, always with clear conversion rules. Suggested tables:

| Table | Principal fields |
|---|---|
| `activity_intervals` | `id`, `start_utc_ms`, `end_utc_ms`, `app_bundle_id`, `domain_host_nullable`, `productivity_class`, `activity_state`, `rule_id_nullable`, `rule_version`, `source`, `quality_flag` |
| `classification_rules` | `id`, `rule_type`, `pattern`, `productivity_class`, `priority`, `enabled`, `version`, `effective_at_utc_ms` |
| `collector_events` | `id`, `event_time_utc_ms`, `event_type`, `source`, `minimal_payload`, `processed_at_utc_ms` (short retention; must not contain sensitive contents) |
| `daily_aggregates` | `local_date`, `timezone`, `productive_active_s`, `productive_passive_s`, `unproductive_s`, `undefined_s`, `ignored_s`, `inactive_s`, `unknown_gap_s`, `configuration_version`, `computed_at_utc_ms` |
| `weekly_aggregates` | `week_start_local_date`, `timezone`, `metrics_json`, `configuration_version`, `computed_at_utc_ms` |
| `reference_totals` | `id`, `local_date`, `reference_timezone`, `metric_name`, `productive_seconds`, `source_type`, `imported_at_utc_ms` |
| `settings` | `key`, `value_json`, `version`, `updated_at_utc_ms` |
| `health_events` | `id`, `occurred_at_utc_ms`, `kind`, `details_code`, `resolved_at_utc_ms` |
| `notification_history` | `id`, `type`, `sent_at_utc_ms`, `week_key`, `snoozed_until_utc_ms` |

**Invariants:** `end > start`; events have stable IDs; interval transitions are transactional; unique event deduplication keys; aggregate jobs are idempotent; database migrations are versioned. `daily_aggregates` are caches and always reconstructible from retained intervals. Historical rebuild is limited when raw intervals have expired.

**Retention defaults:** 90 days detailed intervals, 14 days minimal event diagnostics, 365 days daily/weekly summaries; all configurable, with immediate complete deletion. Store app/domain identifiers only, without raw web content. Protect storage with file permissions and the user's existing disk encryption; encryption-at-rest beyond FileVault may be a future feature if required.

## 10. Algorithms and edge conditions

### 10.1 Interval reducer pseudocode

```text
onEvent(event):
  validate timestamp, source, order, and permissions
  advanceCurrentState(to: event.effectiveTime)
  if event denotes lock/sleep/pause:
    close current credited interval
    transition to inactive or unknown/paused
  else if event denotes wake/unlock/resume:
    begin a new observation state; never backfill missed time
  else if event denotes foreground or eligible browser change:
    close prior classified interval at the effective time
    resolve new classification (may be undefined)
  else if event denotes real input:
    reset idle boundary and transition to active
  else if idle threshold crossed:
    active -> passive -> inactive per configured thresholds
  atomically persist completed intervals and checkpoint
```

The reducer should split an ongoing interval at the 2-minute and 7-minute thresholds based on the timestamp of last input, rather than merely changing state at a sampling tick. For a browser host update while idle, retain explicit attribution rules and avoid guessing that the user is engaged with a newly navigated page.

### 10.2 Forecast and pacing

Let `P` be productive hours this week and `R` the remaining eligible scheduled hours. Let `y` be a bounded productive yield estimated from recent usable workdays (historical productive / valid scheduled observation time, constrained to [0, 1]). Then a baseline forecast is `F = P + R * y`.

- Mark forecasts low confidence if fewer than three distinct usable workdays or more than 10% of scheduled observed time is unknown.
- Show `required_remaining = max(0, 35 - P)` and `headroom = max(0, 40 - P)` prominently whether or not the forecast is available.
- `required_daily_avg = required_remaining / remaining_workday_equivalents`; include partial day fractions and never divide by zero.
- Show the projection's underlying assumptions (planned days/hours and recent yield); avoid precision beyond minutes in UI.
- Evaluate warnings only when predictions are adequately supported; do not turn low-quality data into high-confidence behavioral recommendations.

### 10.3 Mandatory edge-case matrix
- App switches while user is already passive.
- Browser extension sends a stale event after foreground app switches away.
- Two displays with one active foreground application; never count two simultaneous apps.
- Lock, Fast User Switching, logout, power nap, sleep, wake, crash, manual pause.
- Daylight-saving transitions, timezone changes, travel, cross-midnight work, Monday week boundary.
- Clock moved backward/forward, out-of-order collector events, duplicate notifications, replayed extension messages.
- Browser absent/restricted, Accessibility permissions denied or revoked, macOS OS updates.
- Overnight long idle period; no accrual beyond stop threshold.
- Multiple user accounts on same computer; do not mix identities.
- Reference report day boundaries differ from local timezone, or another device contributes to employer totals.

## 11. Security, privacy and permissions

- **Minimize data:** application bundle IDs; opted-in browser hostnames; event timestamps and interval state only. No PHI/PII payload collection.
- **Permissions:** Request or explain only those required by the chosen APIs. App activation and idle observation may not require the same permissions as window-title or webpage inspection; validate in an engineering spike. Do not request Screen Recording merely to get app names. Avoid it entirely in MVP.
- **Extension:** Only transmit active-tab hostname when that browser is foreground; validate messages and grant least-privilege host/tab permissions. Do not record private/incognito sessions.
- **Storage:** Local SQLite in `~/Library/Application Support/ProductiveHours/`, least-privilege access, retention and deletion. No plaintext debug logging of sensitive metadata.
- **Health indicators:** Surface current permission status, extension connectivity, last successful event, and tracking-gap count.
- **Managed Mac:** If a feature is blocked by MDM, enterprise browser settings, or policy, degrade gracefully and tell the user; never bypass the restriction.
- **Threat model:** malicious extension sender, another local process querying the messaging host, corrupted database, unexpected permission revocation, accidental leakage through diagnostic logs, and wrong attribution after sleep/crash.

## 12. Non-functional requirements

| ID | Requirement | Target |
|---|---|---|
| NFR-01 | Interface refresh | Within 60s of new productive time |
| NFR-02 | Foreground attribution | Within 5s under normal operation |
| NFR-03 | Tracking continuity | No unmarked credit across lock/sleep/crash |
| NFR-04 | Resource use | Aim for <1% average CPU during ordinary idle monitoring and <150MB resident memory, subject to profiling on target Macs |
| NFR-05 | Startup | Menu bar usable within 3s on a typical supported Mac |
| NFR-06 | Data integrity | No duplicate or overlapping credited intervals, including after crash recovery |
| NFR-07 | Local privacy | Zero outbound telemetry in V1 |
| NFR-08 | Usability | Full keyboard navigation, VoiceOver names, reduced-motion/high-contrast support |
| NFR-09 | Packaging | Signed, notarized, reproducible release build; no root required |
| NFR-10 | Testability | Core engine, rule evaluator, aggregation, and forecast fully deterministic under fake-clock tests |

These are engineering targets, not verified performance claims.

## 13. Testing strategy and acceptance scenarios

**Unit:** Event reducer/state transitions; rule precedence; interval slicing; classification changes; UTC/local calendar aggregation; pacing/forecast; notification deduplication; CSV validation.

**Integration:** App foreground notifications; real idle observation; sleep/lock; browser Native Messaging; extension disconnected/reconnected; persistence transaction/recovery; login behavior.

**End-to-end:** At least one full 8-hour controlled session and one Monday–Sunday simulated dataset, with test scripts using fake clocks for long elapsed-time scenarios.

**Critical acceptance cases:**
1. **Nine-minute idle:** Productive source with no input for 9 minutes under `start=2m, passive duration=5m` credits exactly 2m Active + 5m Passive + 2m Inactive.
2. **Switch classification:** 10m IDE Productive + 5m unrelated site Unproductive = 10m Productive, with no overlap.
3. **Browser unknown:** Extension missing: browser time is Undefined, not Productive, unless explicit fallback rule is enabled.
4. **Cross-week:** 20m productive Sunday 23:50–Monday 00:10 divides 10m into each week, with correct timezone.
5. **Sleep:** Sleep for 3h after input; no extra credited time after sleep start.
6. **Crash recovery:** Restart after 45m downtime; mark unresolved interval unknown rather than silently awarding 45m.
7. **Target math:** At 34h, show 1h to minimum and 6h to maximum; at 38h, show minimum met and 2h headroom; at 41h, show 1h over maximum without negative headroom.
8. **Rule precedence:** Domain-specific exclusion overrides browser-level Productive classification.
9. **Timezone and DST:** Intervals preserve elapsed seconds while daily calendar grouping follows selected timezone.
10. **Privacy audit:** No full URL, page title, content, key code, screenshot, or typed text anywhere in stored rows or logs.
11. **Calibration:** Imported known sample produces mathematically correct per-day and weekly differences; unknown reference fields are not silently inferred.
12. **Managed-device degradation:** Missing permissions or blocked extensions produce explicit Limited Coverage/Unknown gaps; no bypass attempts.

**Calibration success criterion:** For a voluntary 5-day comparison using a matching metric, timezone and device scope, report median daily absolute error and weekly discrepancy. A stretch goal is weekly error <=10%, but do **not** make it a hard release gate when employer configuration is unknown. Maintain an explicit known-differences list.

## 14. Implementation phases and agent work breakdown

### Phase 0 — Platform feasibility spike
- Create bare SwiftUI menu-bar prototype.
- Verify foreground app API, idle time API, screen lock/wake/sleep notifications and real permissions on actual target macOS.
- Validate whether a Chromium Native Messaging extension can be installed under the intended distribution/MDM policy.
- Record an architecture decision explaining chosen APIs, limits, sandbox/notarization strategy and privacy boundaries.

**Exit:** Demonstrate reliable timestamped transitions across app switch, 2m idle, lock, and wake. No unverified assumptions about permissions.

### Phase 1 — Core tracking MVP (P0)
- SwiftUI shell and onboarding.
- Foreground + input-idle + lock/sleep collectors.
- Pure event reducer with 2m/5m defaults and typed intervals.
- App-level classification UI and SQLite schema/migrations.
- Weekly 35–40h metrics, remaining targets, basic menu bar display.
- Unit/integration tests for all time-accounting invariants.

**Exit:** App produces accurate time totals for controlled native-app usage, even across restarts.

### Phase 2 — Browser fidelity and pacing (P0/P1)
- Chrome/Edge extension and Native Messaging bridge, with hostname-only collection.
- Domain classification priority and Undefined queue.
- Forecasting, scheduled workdays, projection confidence, daily/weekly history.
- Notifications and status degradation.

**Exit:** User can work in IDE, browser, and collaboration apps for a full day and receive coherent weekly pacing totals.

### Phase 3 — Calibration, hardening and distribution (P1)
- ActivTrak reference import/manual totals and comparison diagnostics.
- Rule history/recalculation preview, export, retention and data deletion.
- Performance/energy profiling, crash recovery, signed/notarized installer, permission regression tests.
- Document initial setup and limitations on company-managed devices.

**Exit:** Signed macOS build that runs reliably for a full week and explains discrepancies honestly.

### Phase 4 — Optional enhancements (P2; out of V1)
- Safari/Firefox browser adapters.
- User-consented local calendar integration to display offline meetings separately.
- Better statistical forecast intervals and week-over-week trend reports.
- Optional encrypted at-rest database and local widgets.
- ActivityWatch import if feasible and useful, but do not make it a runtime dependency.

## 15. Definition of Done

A release is ready when:
- The signed app can be installed on a permitted macOS device without elevated privileges.
- It tracks native apps and at least one supported browser at site granularity, with accurate state transitions and visible gaps.
- It produces correct **Productive Active + Productive Passive** totals under fixture tests and supports a 35–40h weekly budget.
- It shows to-minimum/headroom, a clearly labeled projection, history, configurable classifications, and non-spammy alerts.
- It does not record content, screenshots, keystrokes, full URLs, or send telemetry.
- It survives sleep/wake/restart; an 8-hour soak and a weeklong acceptance run reveal no double counting.
- A user can calibrate against an authorized external summary and see discrepancies without any hidden ActivTrak access.
- Setup, permission denial, MDM limitations, data deletion, and accuracy caveats are documented.

## 16. Decisions and outstanding validation

**Defaults selected for implementation:** 35–40h/week; Monday start; Mon–Fri planned days; 9:00–17:00 planned schedule; passive begins at 2m; passive lasts 5 additional minutes; Chrome first; no cloud; browser domains only; manual calibration; 90-day interval retention.

**Validate before implementation, without blocking MVP architecture:**
- Whether the user's actual ActivTrak workspace has different passive start/stop settings or uses a different tracked schedule/timezone.
- Whether reports use Productive or a narrower Active-only metric; Productive is assumed.
- Which apps/sites the employer classifies as Productive and whether browser extension installation is permitted.
- Whether the official report includes other devices or offline meetings; the app models one Mac only.
- Which macOS version, CPU architecture, and managed-browser restrictions apply.

## 17. Primary references

- ActivTrak — [Active Time and Passive Time](https://support.activtrak.com/hc/en-us/articles/360026990372-Active-Time-and-Passive-Time) (updated Aug 31, 2026).
- ActivTrak — [Activity Classification](https://support.activtrak.com/hc/en-us/articles/210214426-Activity-Classification) (updated Jul 14, 2026).
- ActivTrak — [Productivity by User](https://support.activtrak.com/hc/en-us/articles/25556947348635-Productivity-by-User) (updated Jul 14, 2026).
- ActivTrak — [Understanding the ActivTrak Agent](https://support.activtrak.com/hc/en-us/articles/43938170619931-Understanding-the-ActivTrak-Agent) (updated Oct 29, 2026).
- Apple Developer — [NSWorkspace](https://developer.apple.com/documentation/appkit/nsworkspace), [MenuBarExtra](https://developer.apple.com/documentation/swiftui/menubarextra), [UNUserNotificationCenter](https://developer.apple.com/documentation/usernotifications/unusernotificationcenter). Verify exact OS API and permission behavior during Phase 0.

---

**Implementation handoff:** Build the deterministic interval-accounting core and tests *before* building a sophisticated UI. Avoid broad permissions, unverified direct parity claims, and any attempts to interact with the employer's monitoring agent. Make uncertainty and missing data visible by design.
