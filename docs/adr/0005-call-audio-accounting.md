# Call audio accounting

Decision, November 2, 2026: treat observed Zoom or Discord audio IO as productive work, including muted calls. User explicitly accepted the heuristic rather than delaying on microphone-test false positives. No microphone permission, recording, audio tap, meeting title, participant list or message inspection is required.

The public CoreAudio process list supplies input/output flags. Either flag is sufficient. Known helper identities are aggregated per app. Both idle baselines were false; both user-tested calls activated the flags and cleared them on leaving. This does not prove every call state or device configuration will behave identically.

The collector samples with the existing approximately five-second activity cadence. The reducer accepts a ten-second call evidence lease. A missing refresh expires at an exact interval boundary. Read failure clears the lease; normal foreground accounting continues. Sleep, session barriers, pause and collector failure prevent credit. Resume and crash recovery require fresh evidence. Existing platform limits on immediate lock observation still apply.

Call time uses the existing single interval ledger. While input is recent it is active productive; after the active threshold it is passive productive, without the ordinary passive timeout. It is attributed to the call app, independent of foreground app switches. Simultaneous calls use deterministic app order and never add overlapping seconds. No input event is invented and the real idle age remains unchanged when the call ends.

Explicit ignored call-app rules, ignored foreground sources and known private browser windows suppress call credit. Otherwise call evidence overrides ordinary app productivity classification. Call intervals have reason `call_audio`; ordinary classification-history recalculation preserves them. User-declared timers remain separate and may overlap, so their totals are not added automatically.

The optional call lease decodes absent in old checkpoints. The SQLite schema stays unchanged. Regression tests cover long listening calls, expiry, stop, pauses/barriers/failure, restart, legacy checkpoint decoding, privacy exclusions, input-only/output-only activity, and no duplicate credit. Persistence testing covers re-open and rule recalculation.
