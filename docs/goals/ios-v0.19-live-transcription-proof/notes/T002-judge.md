# T002 Judge - Live Proof Slice Decision

## Decision

Approved.

## Rationale

The Scout evidence proves the current installed build has the full live path
ready: microphone allowed, Groq key configured in the app, App Group idle, and
WDA control available. The safest useful slice is therefore a physical proof
run, not product implementation.

The proof must reject the core misfire: a fake or directly staged transcript
being mistaken for a provider-produced transcript.

## Approved Worker Objective

Run one physical live transcription proof on iPhone-preview build `0.1.0 (10)`:

1. Confirm App Group starts idle/no transcript.
2. Use Foil app controls to record a repeated sterile phrase.
3. Use Foil app controls to transcribe the recording through the configured
   provider.
4. Capture sanitized proof that App Group reached complete/hasTranscript only
   after the app Transcribe action.
5. Insert through Foil Keyboard into a fresh sterile Notes note.
6. Capture sanitized pre/post/cleanup receipts proving exact-once insertion and
   idle/no transcript cleanup.

## Allowed Files

- `docs/goals/ios-v0.19-live-transcription-proof/**`
- `scripts/**` only for a narrow harness proof/bug fix if required
- `FoiliOS/**` only if a blocking product bug is discovered and the fix remains
  narrowly scoped

## Verification

- `scripts/ios-physical-harness.py status --wda-url http://192.168.1.40:8100`
- App Group summary before recording is idle/no transcript.
- WDA source/fetch metadata proves app control path without committing raw
  source.
- App Group summary after app Transcribe is complete/hasTranscript with
  transcript hash/length only.
- Sanitized WDA receipts prove Foil Keyboard pre-insert Insert latest enabled.
- Sanitized WDA receipts prove post-insert Notes contains the expected sterile
  transcript exactly once or a clearly equivalent repeated transcript.
- Sanitized cleanup/App Group receipt proves idle/no transcript afterward.
- `node /Users/neonwatty/.codex/plugins/cache/goalbuddy/goalbuddy/0.3.8/skills/goalbuddy/scripts/check-goal-state.mjs docs/goals/ios-v0.19-live-transcription-proof/state.yaml`
- `git diff --check`
- targeted secret/raw-content scan over touched files

## Stop Conditions

- The phone locks, disconnects, or requires user approval.
- Provider key is missing or would need to be printed.
- Microphone permission requires manual action.
- Audio cannot produce a recognizable sterile transcript after two attempts.
- Notes exposes private content that cannot be isolated.
- Raw WDA source, screenshots, or private content would need to be committed.
