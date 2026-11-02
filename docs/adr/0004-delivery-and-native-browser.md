# ADR 0004: Implementation delivery and native browser transport

Status: implemented; interactive and release verification deferred at user request.

The user asked to finish implementation before returning to verification. Phase 0's manual gate no longer blocks writing the later modules. Tests continue to run as part of development; unverified OS behavior must remain identified.

## Delivered ownership

ActivityCore owns event reduction, classification, half-open interval accounting, calendar metrics, forecasting, notification policy and reference parsing. Persistence owns SQLite transactions, overlap enforcement, checkpoint recovery data, retention, recalculation snapshots and audit history. PlatformCollectors owns OS observations and opt-in browser scripting. TrackingService serializes event processing and commits state before publishing durable metrics. SwiftUI owns presentation and user commands.

Use the system SQLite library through a small bound-parameter wrapper rather than introducing GRDB for this first deliverable. This keeps the package buildable offline with the installed toolchain. Integration tests exercise real databases, rollback, reopen, idempotent retry, retention and corruption. Revisit the wrapper only if the query/migration surface grows materially.

## Browser adapter change

Use Chrome/Edge's documented scripting dictionary, with explicit Automation consent, as the initial transport. The user challenged the assumption that an extension is required. Native scripting avoids an extension/native-host installation and associated local IPC trust boundary. The app checks browser foreground and incognito mode, reads only the active tab's URL transiently, then stores a validated hostname. No page script or document content is read. Results expire after ten seconds and must still match the foreground application when delivered.

The original PRD is retained. Its mandatory extension implementation is superseded by this transport decision; domain attribution, privacy and failure behavior remain acceptance obligations. Additional browsers are deliberately unsupported until their private-mode semantics are verified.

Sources: [Chromium scripting dictionary](https://chromium.googlesource.com/chromium/src.git/+/lkgr/chrome/browser/ui/cocoa/applescript/scripting.sdef), [Chromium AppleScript design](https://www.chromium.org/developers/design-documents/applescript/), [Apple Events entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.automation.apple-events).

## Meetings and privacy

The supplied APIs do not establish a trustworthy generic call signal across Zoom, Teams and Discord. Ship a timed explicit work-meeting record with user-declared provenance, bounded end time and 30-second recovery checkpoints. Show it separately so listening time remains visible without claiming automatic detection or double counting it in the digital estimate. Automatic call detection is an unresolved feature limitation, not a verified implementation.

## Remaining release gates

Public session/display/sleep observers are implemented, but immediate screen-lock coverage while the display remains awake is unproven. Denied/revoked permissions, private-mode transitions, launch-at-login, notification delivery, accessibility, resource use, minimum-OS support and real 8-hour/weeklong runs require interactive verification. Developer ID signing and notarization require the user's distribution identity. Build scripts implement that workflow without submitting or publishing anything automatically.
