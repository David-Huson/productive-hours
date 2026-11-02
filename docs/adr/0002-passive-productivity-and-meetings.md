# ADR 0002: Passive productivity and meeting evidence

Status: independent activity/productivity types implemented; meeting policy and detection pending feasibility.

## Finding

The Phase 0 prototype initially represented only activity state. It had no productivity class, classification rules, meeting detector or persisted ledger. Its Passive label did not mean productive or unproductive.

On October 31, 2026, the user clarified that listening in a work call should count as productive despite no typing, while leaving the computer unattended should not count as productive engagement. Named examples were Zoom, Teams and Discord.

## Implemented boundary

`ActivityClassification` carries independent productivity and activity values. Only Productive + Active or Productive + Passive is eligible for productive credit. Inactive and Unknown never count, regardless of productivity. Undefined and Ignored are not productive. A full 4-by-4 test matrix covers this rule.

Diagnostic observations default to Undefined because no classification rules exist yet. The popover exposes that value. No database, call detection or productive total is introduced by this change.

## Difference from the original PRD

The PRD's fixed seven-minute cutoff also stops credit during a silent meeting. Meeting-aware credit beyond that cutoff therefore requires an explicit policy extension, not just marking Zoom productive. Retain the original PRD as the source document and track this refinement here.

No input alone cannot distinguish reading/listening from being away. Under the existing defaults, a productive app can retain Active grace for two minutes and Passive credit for another five. A later sleep event must not retroactively relabel that whole span as unproductive. Actual system sleep and lock remain Inactive immediately, even when a meeting application is open.

## Meeting policy to validate

- A running or foreground meeting app is not proof of a call. An established call is not proof that the call is work-related. User classification determines productivity; separate evidence determines whether a call is ongoing.
- A proposed meeting-aware profile may keep a verified productive call Passive beyond the ordinary cutoff while the session is awake/unlocked. Do not fabricate input or reset last-input time.
- Require fresh, bounded-lifetime call evidence, with explicit start/end and collector health. An ended call must not grant a fresh seven-minute window without actual input.
- Public, privacy-preserving call-state observation for Zoom, Teams and Discord is unverified. Microphone use alone cannot prove a meeting or cover muted listening. Do not inspect conversation text, titles, audio or video.
- If automatic evidence is unavailable, offer explicit user-declared meeting time with provenance and a bounded end time. Keep manual time separate from the automatic estimate unless the user explicitly selects a different target basis.
- A background call and foreground app must share one interval owner. Never add two simultaneous durations. Foreground exclusion conflicts require a documented precedence decision before implementation.
- Display sleep and system sleep must be tested separately. The current conservative display-sleep barrier can undercount an audio call; do not remove it before lock detection is reliable.

## Required tests before enabling meeting credit

Productive and unproductive passive intervals remain distinct after database round trips and aggregation. Cover a 60-minute muted work call, an idle open meeting app without a call, an unproductive call, call end while already beyond the idle cutoff, stale/disconnected call evidence, pause/lock/system sleep during a call, restart during a call, and background-call/foreground-app overlap. Reclassification must preserve rule version and evidence provenance.
