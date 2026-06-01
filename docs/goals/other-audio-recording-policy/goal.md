# Other Audio Recording Policy

## Objective

Make Foil's behavior toward other audio while recording explicit, default-safe, and verifiable: by default Foil must not pause, silence, or dampen other audio; any supported audio-pausing behavior must be opt-in; and macOS/Bluetooth input-mode effects must be investigated and handled honestly through detection, guidance, or a bounded mitigation if one is technically sound.

## Original Request

"i notice that when we use the app all other audio is silenced - we should not do that - lets work out a plan to stop that from happening... either the user can have audio on or off when using the app, and by default audio should be on... should we roll in potential fixes to macOS / Bluetooth input mode quieting audio when in use as well? ... plan this out with goalbuddy prep"

## Intake Summary

- Input shape: `specific`
- Audience: Foil users who record while music, calls, browser media, or system audio may already be playing.
- Authority: `requested`
- Proof type: `test`
- Completion proof: Verified implementation and/or documented decision showing that default recording does not intentionally affect other audio, the opt-in audio-pausing control is clear and tested, and Bluetooth/macOS input-mode behavior has either a verified mitigation or a clear in-app/documented warning.
- Goal oracle: A manual audio smoke matrix plus automated tests prove the default path does not call Foil's other-audio control path, opt-in browser/media pausing only runs when enabled, diagnostics identify the active policy, and Bluetooth/input-mode findings are recorded with product treatment.
- Likely misfire: Fixing or renaming only the existing browser-media pause setting while ignoring OS/device-level audio route changes, or promising a universal "pause all audio" / "duck all audio" behavior that macOS does not safely support.
- Blind spots considered: Existing persisted settings may already enable browser media pause; macOS Bluetooth headset profiles can degrade or interrupt playback when their mic is used; Foil may not be able to control third-party app/system volume safely; copy must not imply unsupported universal audio control.
- Existing plan facts:
  - Default user-facing behavior should be audio on / unaffected.
  - Start with a binary setting, not a slider.
  - Current code has a browser media pausing path that should remain opt-in only if retained.
  - Bluetooth/macOS input-mode quieting should be considered separately from intentional Foil browser pausing.

## Goal Oracle

The oracle for this goal is:

`Automated tests plus a manual smoke matrix show: default recording leaves other audio unaffected by Foil policy; the opt-in setting is required before Foil attempts supported media pausing; diagnostics clearly record the selected policy; and Bluetooth/input-device quieting has a verified mitigation or explicit product guidance backed by evidence.`

The PM must keep comparing task receipts to this oracle. Planning, discovery, a passing tiny slice, or a clean-looking board is not enough. The goal finishes only when a final Judge/PM audit maps receipts and verification back to this oracle and records `full_outcome_complete: true`.

## Goal Kind

`specific`

## Current Tranche

Complete the audio-policy correction and investigation tranche:

1. Scout the current implementation and observed behavior boundaries without changing product code.
2. Judge the first safe implementation slice.
3. Implement the default-off, binary, user-facing policy for intentional Foil audio pausing with tests and diagnostics.
4. Investigate macOS/Bluetooth input-mode behavior and either implement a bounded user-facing mitigation or record why the safe product treatment is guidance/warning rather than control.
5. Run a final audit against the oracle.

## Non-Negotiable Constraints

- Default behavior: Foil must not intentionally pause, silence, or dampen other audio.
- Any other-audio interference controlled by Foil must be opt-in.
- Do not promise system-wide audio control unless the implementation is safe, public-API based, and verified.
- Do not use private APIs or fragile UI scripting to manipulate other apps' volume.
- Preserve production-user safety: avoid migrations that unexpectedly change a user's explicit prior setting unless the decision is deliberate and documented.
- Keep browser-media pause copy honest if it remains limited to Chrome/Chromium or other specific supported apps.
- Manual verification should distinguish Foil policy from macOS/device behavior.

## Stop Rule

Stop only when a final audit proves the full original outcome is complete.

Do not stop after planning, discovery, or Judge selection if a safe Worker task can be activated.

Do not stop after a single verified Worker package when the broader owner outcome still has safe local follow-up work. Advance the board to the next highest-leverage safe Worker package and continue unless a phase, risk, rejected-verification, ambiguity, or final-completion review is due.

Do not stop because Bluetooth behavior is OS/device-dependent. Record the exact blocker, create the best safe product treatment task, and continue with local verification and documentation that can still move the goal forward.

## Slice Sizing

Safe means bounded, explicit, verified, and reversible. It does not mean tiny.

A good task is the largest safe useful slice: for this goal, the first Worker should likely cover the binary default-off policy, UI copy, diagnostics, and tests together once Judge confirms the file scope.

## Canonical Board

Machine truth lives at:

`docs/goals/other-audio-recording-policy/state.yaml`

If this charter and `state.yaml` disagree, `state.yaml` wins for task status, active task, receipts, verification freshness, and completion truth.

## Run Command

```text
/goal Follow docs/goals/other-audio-recording-policy/goal.md.
```

## PM Loop

On every `/goal` continuation:

1. Read this charter.
2. Read `state.yaml`.
3. Run the bundled GoalBuddy update checker when available and mention a newer version without blocking.
4. Re-check the intake: original request, input shape, authority, proof, blind spots, existing plan facts, and likely misfire.
5. Work only on the active board task.
6. Assign Scout, Judge, Worker, or PM according to the task.
7. Write a compact task receipt.
8. Update the board.
9. If safe local work remains, choose the next largest reversible Worker package and continue unless blocked.
10. If a problem, suggestion, or follow-up should become a repo artifact, create an approved issue/PR or ask the operator whether to create one.
11. Review at phase, risk, rejected-verification, ambiguity, or final-completion boundaries.
12. Finish only with a Judge/PM audit receipt that maps receipts and verification back to the original user outcome and records `full_outcome_complete: true`.
