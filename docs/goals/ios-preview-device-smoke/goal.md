# Foil iOS Preview Device Smoke

## Objective

Resume the existing Foil iOS keyboard prototype from `codex/ios-keyboard-prototype` and prove, on the online unlocked `iPhone-preview`, that the native iOS app and custom keyboard can be built, signed, installed, enabled, and used for the smallest real dictation loop: containing-app recording/transcription plus keyboard insertion into host apps.

## Original Request

The user agreed the next milestone is installing the iOS prototype on the preview iPhone, then asked to make a detailed GoalBuddy prep plan, possibly a conveyor of boards, and do it.

## Intake Summary

- Input shape: `existing_plan`
- Audience: Foil owner/developer evaluating whether an iPhone analogue is technically viable.
- Authority: `approved`
- Proof type: `demo`
- Completion proof: the preview iPhone has a current Foil iOS build installed with the keyboard enabled, and receipts prove or precisely block physical-device recording, transcription, and text insertion into real target apps.
- Goal oracle: a repeatable physical-device smoke transcript showing the app installed on `iPhone-preview`, the Foil keyboard enabled and selected, microphone capture handled by the containing app, a Groq/Grok-compatible transcription produced without leaking secrets, and latest text inserted through `textDocumentProxy.insertText` into at least one real host app.
- Likely misfire: treating simulator insertion proof as enough while the real iPhone fails on signing, App Group provisioning, keyboard enablement, microphone permission, background handoff, or host-app insertion.
- Blind spots considered: custom keyboard sandboxing, Open Access/App Group behavior, real-device provisioning for app groups, microphone access in extensions versus containing app, URL handoff lifecycle, keyboard reset/cycle quirks, secure fields that reject custom keyboards, simulator/device divergence, secret handling, and preserving the earlier prototype branch evidence.
- Existing plan facts: continue from `codex/ios-keyboard-prototype`; use the preview iPhone, which is online/open/unlocked; use the machine's Groq/Grok key only for local testing; create a branch for this tranche; use GoalBuddy receipts and acceptance evidence; avoid committing secrets or private content.

## Goal Oracle

The oracle for this goal is:

`On codex/ios-preview-device-smoke, receipts prove or narrowly block a physical iPhone-preview install, keyboard enablement, containing-app record/transcribe flow, and real-host insertion flow for the existing Foil iOS custom keyboard prototype.`

The PM must keep comparing task receipts to this oracle. Planning, a generated project, a simulator-only pass, a successful build without install, or a keyboard screenshot without inserted host text is not enough. The goal finishes only when a final Judge/PM audit maps receipts and verification back to this oracle and records `full_outcome_complete: true`.

## Goal Kind

`existing_plan`

## Current Tranche

Complete the preview-device smoke tranche. Start with a read-only reality check, then proceed through the largest safe useful slices: real-device signing/build, physical install/launch, keyboard enablement, recording/transcription, host-app insertion matrix, issue/PR handoff, and final audit.

## Conveyor Plan

This board is the parent conveyor. It should only promote a child board when a slice becomes large enough to need its own focused run; otherwise the parent board keeps moving.

1. **Device Reality And Signing Scout**: prove the checked-out branch, project shape, available devices, signing team/App Group state, and test key availability without printing secrets.
2. **Physical Build And Install**: make the current iOS prototype build for `iPhone-preview`, fixing signing/provisioning only inside the iOS prototype files.
3. **Keyboard Enablement Smoke**: install and launch, enable Foil Keyboard in Settings, and document the reset/cycle behavior required to make it visible.
4. **Voice Handoff Smoke**: prove containing-app microphone recording on the device, then prove transcription using the local test key or record the exact blocker.
5. **Insertion Matrix Smoke**: insert latest text through the custom keyboard into real host apps, starting with Notes or Reminders, then Safari and Messages only if privacy-safe.
6. **Handoff Artifacts**: update the existing iOS issue and open or prepare a PR into `codex/ios-keyboard-prototype` when code changes are made.
7. **Final Audit**: try to disprove that the iPhone path works; record the strongest remaining failure mode and evidence.

Potential child boards:

- `ios-device-signing-provisioning`: only if App Group signing/provisioning becomes its own multi-step blocker.
- `ios-keyboard-enable-reset-matrix`: only if keyboard enablement/reset behavior needs repeated per-iOS-version documentation.
- `ios-voice-handoff-device`: only if microphone/background transcription needs a separate architecture slice.
- `ios-insertion-target-matrix`: only if the real-app insertion matrix grows beyond the first smoke pass.

## Non-Negotiable Constraints

- Do not merge this prototype directly to `main`.
- Do not commit API keys, recordings with sensitive speech, private screenshots, message content, contacts, or device-specific secrets.
- Treat simulator success as supporting evidence only; it cannot prove physical-device microphone, keyboard lifecycle, signing, or background behavior.
- Respect unrelated worktree changes and do not revert them.
- Use native Swift/iOS patterns and keep the prototype intentionally small.
- If a field or app rejects custom keyboards, record that as matrix evidence instead of trying to bypass platform restrictions.
- Prefer evidence from commands, screenshots, logs, or direct device inspection over optimistic UI.

## Stop Rule

Stop only when a final audit proves the full original outcome for this tranche is complete.

Do not stop after planning, discovery, or Judge selection if a safe Worker task can be activated.

Do not stop after a single verified Worker package when physical-device install, keyboard enablement, recording/transcription, or insertion still has safe local follow-up work.

Do not stop because a slice needs owner input, credentials, production access, destructive operations, or policy decisions. Mark that exact slice blocked with a receipt, create the smallest safe follow-up or workaround task, and continue all local, non-destructive work that can still move the goal toward the full outcome.

## Canonical Board

Machine truth lives at:

`docs/goals/ios-preview-device-smoke/state.yaml`

If this charter and `state.yaml` disagree, `state.yaml` wins for task status, active task, receipts, verification freshness, and completion truth.

## Run Command

```text
/goal Follow docs/goals/ios-preview-device-smoke/goal.md.
```

## PM Loop

On every `/goal` continuation:

1. Read this charter.
2. Read `state.yaml`.
3. Run the bundled GoalBuddy update checker when available and mention a newer version without blocking.
4. Re-check the intake, especially the likely misfire that simulator proof is mistaken for device proof.
5. Work only on the active board task.
6. Assign Scout, Judge, Worker, or PM according to the task.
7. Write a compact task receipt.
8. Update the board.
9. If safe local work remains, choose the next largest reversible Worker package and continue unless blocked.
10. Create issue/PR handoff artifacts only when the task authorizes them and record links in the receipt.
11. Review at phase, risk, rejected-verification, ambiguity, or final-completion boundaries.
12. Finish only with a Judge/PM audit receipt that maps receipts and verification back to the original user outcome and records `full_outcome_complete: true`.
