# Foil iOS Keyboard State And Target Matrix

## Objective

Continue from `codex/ios-keyboard-prototype` and make the iPhone custom-keyboard prototype reliable enough for the next product-design decision: after one insertion, the keyboard UI, UserDefaults snapshot, and canonical App Group file must agree that the transcript is consumed, and a privacy-safe physical-device insertion matrix must show where Foil Keyboard works or is rejected.

## Original Request

The user asked, "excellent make a detailed plan using goalbuddy prep" after agreeing that the next iOS work should start with the App Group state cleanup, then expand physical-device host-app testing.

## Intake Summary

- Input shape: `specific`
- Audience: Foil owner/developer deciding whether the iPhone path is productizable.
- Authority: `approved`
- Proof type: `demo`
- Completion proof: a merged PR into `codex/ios-keyboard-prototype` proves the keyboard reset persistence fix and records a physical-device insertion/rejection matrix with screenshots, WDA/source receipts, file-state receipts, and explicit residual risks.
- Goal oracle: on the unlocked `iPhone-preview`, after a seeded or spoken transcript is inserted once through Foil Keyboard, WDA shows the host field changed exactly once, the keyboard UI shows no transcript, and `devicectl copy from` of the canonical App Group file also shows idle/no transcript. Matrix rows then prove Notes, Safari blank search/address, Reminders blank item, and at least one secure-field rejection or platform-limited row without preserving private content.
- Likely misfire: fixing only the visible keyboard UI while a stale canonical App Group file can still resurrect a transcript, or growing the host-app matrix using private/personal app state that cannot be committed as evidence.
- Blind spots considered:
  - Keyboard extensions may have different file-write behavior from the containing app.
  - UserDefaults and file-backed App Group state can diverge.
  - Running keyboard extension processes may cache old code or old snapshots until killed/cycled.
  - Safari, Reminders, Messages, and secure fields can expose private data through raw accessibility trees.
  - Secure fields should reject custom keyboards by platform design; that is evidence, not a bug.
  - Large Dynamic Type on the preview phone can hide controls and make screenshots hard to interpret.
  - API keys and transcript content must not leak into committed logs.
  - The previous branch already proved basic install, record/transcribe, Notes insertion, Safari insertion, and live UI reset; this goal must build on that rather than rediscover it.

## Goal Oracle

The oracle for this goal is:

`On codex/ios-keyboard-prototype, physical iPhone-preview receipts prove that keyboard reset persistence is consistent across UI, UserDefaults, and canonical App Group file after insertion, and a privacy-safe host-app matrix records pass/reject/blocker rows for the next target apps.`

The PM must keep comparing receipts to this oracle. A successful build, a simulator pass, or a visible `Ready` label is not enough if the canonical App Group file still contains a consumed transcript.

## Goal Kind

`specific`

## Current Tranche

Fix the reset persistence ambiguity, add enough state observability to disprove stale snapshots, then run the smallest privacy-safe host-app insertion matrix on the physical phone.

## Conveyor Plan

This is a focused child board of the iOS prototype work. Promote another child board only if a slice becomes large enough to deserve its own run.

1. **State Reality Scout**: map current storage paths, current branch state, device/WDA/tunnel availability, and exact stale-state failure mode without editing code.
2. **Reset Persistence Fix**: make keyboard reset clear or overwrite canonical App Group file and UserDefaults from both app and keyboard contexts.
3. **State Inspector Surface**: if needed, add a small debug-only or prototype-only state view in the containing app that shows the app's view of file/UserDefaults snapshots without exposing secrets.
4. **Physical Reset Proof**: build/install on iPhone-preview; seed a transcript; insert once in Notes; prove UI, host text, UserDefaults-derived app state, and canonical file agree.
5. **Privacy-Safe Target Matrix**: run Notes repeat, Safari blank address/search, Reminders blank item, and one secure-field rejection row; Messages only if the operator opens a safe blank self/test context.
6. **Interaction Design Decision**: summarize whether the current Whisperflow-style app/keyboard cycle is acceptable for the next prototype and record the minimal product interaction to build next.
7. **Issue/PR Handoff**: update issue #216, open a PR into `codex/ios-keyboard-prototype`, and merge only after the oracle is satisfied or narrowly blocked.
8. **Final Audit**: try to disprove the goal with the strongest stale-state and privacy-risk checks before declaring completion.

Potential child boards:

- `ios-keyboard-state-store`: only if App Group file/UserDefaults divergence requires a larger storage abstraction.
- `ios-target-matrix-privacy-safe`: only if host-app testing expands beyond the first matrix rows.
- `ios-keyboard-cycle-ux`: only if switching back to Foil Keyboard needs a separate interaction-design/prototype pass.

## Non-Negotiable Constraints

- Do not merge this prototype directly to `main`.
- Do not commit API keys, private browsing trees, Messages content, contacts, personal Reminders, sensitive screenshots, or raw recordings.
- Keep changes scoped to `FoiliOS/**` and this goal unless a Judge explicitly approves more.
- Treat a secure field rejecting Foil Keyboard as expected platform behavior and record it honestly.
- Treat simulator evidence as supporting only; physical-device proof is required.
- Respect unrelated worktree changes and do not revert them.
- Use `docs/acceptance-evidence.md`: name the claim, strongest realistic failure mode, evidence, and residual risk.
- If WDA/device control is unavailable, record the exact blocker and continue with all safe local verification.

## Stop Rule

Stop only when a final audit proves the oracle or records a narrow blocker with no remaining safe local work.

Do not stop after planning, a passing build, a single Notes insert, or a visible keyboard reset. The canonical App Group file must be checked after insertion, because that is the known strongest failure mode.

## Canonical Board

Machine truth lives at:

`docs/goals/ios-keyboard-state-and-target-matrix/state.yaml`

If this charter and `state.yaml` disagree, `state.yaml` wins for task status, active task, receipts, verification freshness, and completion truth.

## Run Command

```text
/goal Follow docs/goals/ios-keyboard-state-and-target-matrix/goal.md.
```

## PM Loop

On every `/goal` continuation:

1. Read this charter.
2. Read `state.yaml`.
3. Re-check the oracle and the known stale canonical App Group file failure mode.
4. Work only on the active task.
5. Assign Scout, Judge, Worker, or PM according to the task.
6. Write a compact receipt under the task and, when useful, a longer note under `notes/`.
7. Update the board.
8. Run the strongest realistic proof before claiming a task is done.
9. Create issue/PR handoff artifacts only when authorized by the active task.
10. Finish only with a final audit receipt that records `full_outcome_complete: true` or a precise blocker.
