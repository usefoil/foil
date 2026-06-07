# T001 Scout - Live Transcription Proof Path

## Result

Done. The current build and device state are ready for a physical live proof.

## Current Readiness

- Worktree: `codex/ios-v0.19-live-transcription-proof`, branched from
  `codex/ios-keyboard-prototype`.
- Installed iPhone-preview app: Foil iOS `0.1.0 (10)`.
- App Group baseline: `Library/foil-keyboard-snapshot.json` is
  `phase=idle`, `hasTranscript=false`.
- WDA project and `iproxy` are present.
- WDA was started and advertised `http://192.168.1.40:8100`.
- Foil app source inspection through a current-app WDA session confirmed:
  - app surface is Foil iOS;
  - microphone row says allowed;
  - provider row says Groq key configured;
  - shared state says ready/no transcript;
  - recording and transcribe controls are present.
- The shell environment does not contain `GROQ_API_KEY` or
  `FOIL_IOS_GROQ_API_KEY`; provider readiness comes from the app's stored
  device credential, not a key printed by this run.

## Recommended Sterile Phrase Strategy

Use a repeated phrase so Whisper can tolerate one bad pickup while still proving
the intended words:

`foil live proof nineteen, foil live proof nineteen, foil live proof nineteen`

Use macOS text-to-speech as the audio source and record that fact in the Worker
receipt. Do not commit audio files.

## Host Target Recommendation

Use Notes as the single sterile host target.

Reasons:

- Previous real-audio smoke and target-app rows already proved Notes can be
  driven safely with WDA.
- Notes avoids Messages privacy risk.
- A fresh note gives a clear exact-once value count without sending anything.

## Evidence Needed To Distinguish Live Transcript From Fake Staging

The Worker must prove all of these in order:

1. App Group starts idle/no transcript.
2. The test uses WDA/app controls or the app URL/command path to start/stop
   recording and tap Transcribe.
3. App or App Group state progresses through listening/processing/complete.
4. The complete snapshot appears after the app Transcribe action, not after
   `stage-transcript` or `completeFakeTranscript`.
5. The complete snapshot receipt records phase, transcript hash, and transcript
   length only.
6. Foil Keyboard pre-insert receipt shows Insert latest enabled in a fresh
   sterile Notes note.
7. Post-insert receipt shows the expected sterile phrase appears exactly once
   or a clearly equivalent repeated transcript appears, and Insert latest is
   disabled.
8. Cleanup receipt shows App Group idle/no transcript and no stale draft state.

## Candidate Worker Slice

Objective: run one physical live transcription proof on build 10, using Foil app
record/stop/transcribe controls, macOS text-to-speech for the sterile phrase,
Foil Keyboard insertion into a fresh Notes note, and v0.18 harness receipts for
state/source proof.

Allowed files:

- `docs/goals/ios-v0.19-live-transcription-proof/**`
- `scripts/**` only for narrow harness fixes required to record sanitized proof
- `FoiliOS/**` only if a blocking product bug is found and approved by Judge

Verification:

- `scripts/ios-physical-harness.py status --wda-url http://192.168.1.40:8100`
- App Group summary before recording is idle/no transcript.
- WDA source/fetch receipts show Foil app recording/transcription state changes
  without committing raw source.
- App Group summary after transcription is complete/hasTranscript with hash and
  length only.
- WDA sanitized receipts prove Foil Keyboard pre/post insert state in Notes.
- App Group reset/cleanup receipt is idle/no transcript.
- `node .../check-goal-state.mjs docs/goals/ios-v0.19-live-transcription-proof/state.yaml`
- `git diff --check`
- targeted secret/raw-content scan over touched files

Stop if:

- the phone locks, disconnects, or requires user approval;
- provider key is missing or a key would need to be printed;
- microphone permission requires manual action;
- audio cannot produce a recognizable sterile transcript after two attempts;
- Notes exposes private content that cannot be isolated;
- a live WDA source would need to be committed to prove the row.
