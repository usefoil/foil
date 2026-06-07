# T001 Scout - Keyboard UX Recovery State

## Result

Done.

## Current State Model

- `FoilKeyboardSnapshot` stores `phase`, optional `transcript`, `message`, and
  `updatedAt`.
- `FoilKeyboardPhase` currently supports `idle`, `handoffRequested`,
  `listening`, `processing`, `complete`, and `failed`.
- `FoilDictationLoopPresenter.keyboardPresentation` correctly treats only
  `.complete` snapshots with a non-empty transcript as "Transcript ready".
- `KeyboardViewController.refreshState` enables Insert latest when any
  non-empty transcript exists, regardless of phase.
- `FoilKeyboardBridge.consumeTranscriptForInsertion()` returns any non-empty
  transcript, regardless of phase, then clears state.

## Highest-Risk Gap

The UI copy and the insertion gate disagree. A stale or malformed snapshot with
`phase=failed`, `phase=processing`, `phase=listening`, or `phase=idle` plus a
leftover transcript can still enable and consume Insert latest. That is exactly
the v0.21 strongest realistic failure mode: the UI can imply "not ready" while
the underlying action still inserts stale text.

## Existing Tests

- `FoilKeyboardBridgeTests` proves a complete transcript inserts once and empty
  transcript clears.
- `FoilDictationLoopPresentationTests` proves current keyboard copy for idle,
  failed, full-access-off, and keyboard-health stale states.
- There is no test proving:
  - non-complete phases with transcripts are not insertable;
  - keyboard button enablement uses the same insertability rule as consumption;
  - malformed/undecodable App Group JSON falls back safely;
  - a blocked/stale state gives a clear operator recovery path.

## Physical Evidence Context

- v0.19 proved live app transcription -> Foil Keyboard -> exact-once Notes
  insertion -> App Group idle cleanup.
- v0.20 proved a Safari single-line insertion row and recorded exact blockers:
  Mail unavailable, Calendar privacy stop, and Foil secure diagnostics not
  reachable through WDA.
- v0.20's Foil secure blocker suggests a useful testability improvement:
  a first-party deep link or command path to expose/focus diagnostics would make
  future secure-field rejection proof less brittle.

## Recommended Slice

Implement a narrow state-safety slice:

1. Add a shared insertability rule on `FoilKeyboardSnapshot`, for example
   `insertableTranscript`, that returns trimmed transcript only when
   `phase == .complete`.
2. Use that rule in `FoilKeyboardBridge.consumeTranscriptForInsertion()`.
3. Use that rule in `KeyboardViewController.refreshState()` for Insert latest
   enabled state and styling.
4. Add tests proving:
   - complete non-empty transcript inserts once and clears;
   - failed/listening/processing/idle snapshots with leftover transcript do not
     insert and clear to idle;
   - keyboard presentation keeps non-complete leftover transcript states in
     recovery/waiting/no-transcript copy.
5. Optionally add a narrow first-party diagnostics opener/focus route only if
   the state-safety slice is green and low-risk.

## Candidate Worker

Allowed files:

- `FoiliOS/Shared/FoilKeyboardBridge.swift`
- `FoiliOS/FoilKeyboard/KeyboardViewController.swift`
- `FoiliOS/Shared/FoilDictationLoopPresenter.swift`
- `FoiliOS/FoilIOSTests/FoilKeyboardBridgeTests.swift`
- `FoiliOS/FoilIOSTests/FoilDictationLoopPresentationTests.swift`
- `docs/goals/ios-v0.21-keyboard-ux-recovery/**`

Verify:

- `xcodebuild test -project FoiliOS/FoilIOS.xcodeproj -scheme FoilIOS -destination 'platform=iOS Simulator,name=<available simulator>' -only-testing:FoilIOSTests/FoilKeyboardBridgeTests`
- `xcodebuild test -project FoiliOS/FoilIOS.xcodeproj -scheme FoilIOS -destination 'platform=iOS Simulator,name=<available simulator>' -only-testing:FoilIOSTests/FoilDictationLoopPresentationTests`
- GoalBuddy state checker.
- Physical sterile receipt showing complete transcript enables Insert latest,
  after insert disables it, and cleanup is idle.
- Targeted secret/raw-content scan.
- `git diff --check`.
