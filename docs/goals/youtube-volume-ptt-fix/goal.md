# Fix YouTube Volume Jump During Push-To-Talk

## Objective

Stop Foil recordings from causing YouTube or other playback to become louder while the push-to-talk key is held, with a verified local mitigation for AirPods/Bluetooth input-output setups and honest handling of any macOS behavior Foil cannot control directly.

## Original Request

"make a detailed plan using goal buddy prep to fix this issue"

The issue being planned is the verified symptom from the preceding investigation: while listening to YouTube in Chrome, holding Foil's push-to-talk key made the music volume increase until recording stopped.

## Intake Summary

- Input shape: `specific`
- Audience: Foil users who listen to YouTube or other audio while dictating, especially with AirPods or other Bluetooth headsets.
- Authority: `requested`
- Proof type: `test + demo`
- Completion proof: A final receipt shows that, on the local machine with YouTube playing and AirPods connected, holding Foil push-to-talk no longer changes macOS output volume; or, if macOS/Bluetooth makes that impossible for a selected Bluetooth mic, Foil prevents or guides users away from the risky configuration and the final audit proves the bounded product behavior.
- Goal oracle: A live local audio smoke matrix that samples `osascript -e 'get volume settings'` before, during, and after Foil recording while YouTube plays, correlated with Foil diagnostics. The default or recommended path must keep output volume stable across the recording window.
- Likely misfire: Adding another generic Bluetooth warning or only disabling browser media control while leaving the default AirPods mic path able to jump system output volume from 38 to 50 during PTT.
- Blind spots considered: macOS may maintain per-route or per-profile Bluetooth output volumes; AirPods as both input and output may enter a different audio mode; Foil may not have a safe public API to suppress route-volume changes; changing the system default input can be intrusive; tests may pass with no Bluetooth hardware while the live symptom persists; cue sounds can distract from the measured YouTube volume issue.
- Existing plan facts:
  - Source inspection did not find Foil writing system output volume.
  - The only direct `volume` setter found was Foil's own `NSSound.volume = 1.0` for cue playback.
  - Live installed-app diagnostics showed `otherAudio: unaffected policy=none` and `browserMediaControl: skipped disabled`.
  - Live polling verified macOS output volume changed from 38 to 50 at the same second Foil started recording, then returned to 38 when Foil stopped.
  - The active setup used AirPods as the default input and default output.
  - A debug live microphone QA attempt failed before recording because the debug app had `microphone_permission_status=not_determined`; it is not proof of the installed-app behavior.

## Goal Oracle

The oracle for this goal is:

`With YouTube playing in Chrome and AirPods connected, a Foil push-to-talk recording on the default/recommended configuration keeps macOS output volume stable in repeated before/during/after samples, and Foil diagnostics explain the active input policy.`

The PM must keep comparing task receipts to this oracle. Planning, discovery, a passing unit test, or a warning that merely describes the problem is not enough. The goal finishes only when a final Judge/PM audit maps receipts and verification back to this oracle and records `full_outcome_complete: true`.

## Goal Kind

`specific`

## Current Tranche

Complete successive safe verified slices until Foil has a product-level fix for the PTT volume jump:

1. Reproduce and isolate the root cause boundary with the installed app, YouTube, AirPods, and output-volume polling.
2. Decide the safest mitigation: prefer a non-Bluetooth input policy when Bluetooth output is in use, or a guided setting if an automatic default would be too intrusive.
3. Implement the chosen mitigation with focused tests, diagnostics, and settings/onboarding copy.
4. Verify with a live smoke matrix that tries to disprove the fix.

## Non-Negotiable Constraints

- Do not use private APIs, fragile UI scripting, or third-party app volume manipulation to control Chrome, YouTube, AirPods, or system output volume.
- Do not claim Foil can universally prevent macOS Bluetooth route or profile behavior unless live evidence proves it.
- Preserve user choice: users who intentionally select a Bluetooth microphone may keep using it, but Foil must make the volume-jump risk explicit and measurable.
- The default or recommended path should avoid the verified AirPods input/output volume jump.
- Keep implementation scoped to recording input policy, diagnostics, settings/onboarding guidance, and tests directly tied to this bug.
- Follow `docs/acceptance-evidence.md`: audio-device behavior requires focused recorder/audio tests and live/manual smoke notes when hardware behavior matters.
- Avoid destructive permission resets unless the user explicitly approves them.

## Stop Rule

Stop only when a final audit proves the full original outcome is complete.

Do not stop after planning, discovery, or Judge selection if a safe Worker task can be activated.

Do not stop after a single verified Worker package when the broader owner outcome still has safe local follow-up work. Advance the board to the next highest-leverage safe Worker package and continue unless a phase, risk, rejected-verification, ambiguity, or final-completion review is due.

## Slice Sizing

Safe means bounded, explicit, verified, and reversible. It does not mean tiny.

A good Worker package for this goal should change behavior users can feel: for example, defaulting away from Bluetooth headset microphones when appropriate, adding a tested "prefer Mac mic while headphones stay output" path, improving diagnostics so the active input policy is auditable, or adding settings/onboarding treatment that directly prevents the bad configuration.

## Canonical Board

Machine truth lives at:

`docs/goals/youtube-volume-ptt-fix/state.yaml`

If this charter and `state.yaml` disagree, `state.yaml` wins for task status, active task, receipts, verification freshness, and completion truth.

## Run Command

```text
/goal Follow docs/goals/youtube-volume-ptt-fix/goal.md.
```

## PM Loop

On every `/goal` continuation:

1. Read this charter.
2. Read `state.yaml`.
3. Run the bundled GoalBuddy update checker when available and mention a newer version without blocking.
4. Re-check the verified symptom, likely misfire, constraints, and oracle.
5. Work only on the active board task.
6. Assign Scout, Judge, Worker, or PM according to the task.
7. Write a compact task receipt.
8. Update the board.
9. If safe local work remains, choose the next largest reversible Worker package and continue unless blocked.
10. Finish only with a Judge/PM audit receipt that maps receipts and verification back to the original user outcome and records `full_outcome_complete: true`.
