# T002 Judge

Decision: approved.

The first implementation slice should tighten insertability around one shared rule: a keyboard snapshot is insertable only when it is in `complete` phase and has a non-empty trimmed transcript. This matches the existing presenter copy and closes the risk that a leftover transcript attached to `failed`, `listening`, `processing`, `handoffRequested`, or `idle` could be inserted later.

Worker objective:

- Add an `insertableTranscript` rule on `FoilKeyboardSnapshot`.
- Use that rule in `FoilKeyboardBridge.consumeTranscriptForInsertion()`.
- Use that rule in `KeyboardViewController.refreshState()` for Insert latest enablement and coloring.
- Preserve reset/recovery for any non-idle or leftover transcript state.
- Add tests proving complete transcripts insert exactly once, blank complete transcripts do not insert, and non-complete leftover transcript snapshots do not insert.
- Add presentation tests proving non-complete leftover transcript snapshots do not advertise `Insert latest`.

Allowed files:

- `FoiliOS/Shared/FoilKeyboardBridge.swift`
- `FoiliOS/FoilKeyboard/KeyboardViewController.swift`
- `FoiliOS/FoilIOSTests/FoilKeyboardBridgeTests.swift`
- `FoiliOS/FoilIOSTests/FoilDictationLoopPresentationTests.swift`
- `docs/goals/ios-v0.21-keyboard-ux-recovery/**`

Verify:

- Run the relevant Swift tests for keyboard bridge and dictation loop presentation.
- Run the GoalBuddy state checker.
- Run `git diff --check`.
- Run a targeted scan over touched files for secrets/private device content.
- If physical WDA is available without user unlock/install action, collect a sterile receipt; otherwise record the physical receipt as the remaining external proof item rather than widening the code slice.

Stop if:

- A test requires private phone content or raw WDA sources.
- The fix requires onboarding redesign or new iOS capabilities.
- The device needs unlock/install/user action.
