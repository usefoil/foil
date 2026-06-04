# Foil iOS Keyboard Onboarding And Full Access UX

## Objective

Turn the working iPhone keyboard prototype into a guided, recoverable first-run experience: a user should understand why Foil needs a custom keyboard and Allow Full Access, be able to configure it, see whether it is healthy, recover from stale state, and complete a real record/transcribe/insert loop on the physical preview iPhone.

## Original Request

The user asked to plan the next iOS product slice after the physical iPhone state-reset and target-app matrix proved that the custom-keyboard architecture works when Allow Full Access is enabled.

## Intake Summary

- Input shape: `specific`
- Audience: Foil owner/developer preparing the iPhone prototype for normal-person usability.
- Authority: `approved`
- Proof type: `demo`
- Completion proof: a PR into `codex/ios-keyboard-prototype` proves onboarding, Full Access health detection, recovery, and the real transcript loop on `iPhone-preview`.
- Goal oracle: starting from a clean or intentionally misconfigured state, the physical iPhone prototype guides the user to enable Foil Keyboard and Allow Full Access, clearly blocks unsafe stale insertion when Full Access is off, recovers/reset state from the app, and completes a record/transcribe/return-to-keyboard/insert flow with post-insert canonical App Group state idle/no transcript.
- Likely misfire: building explanatory screens that look nice but do not actually detect Full Access, do not recover stale App Group state, or only pass with the developer manually configuring Settings out of band.
- Blind spots considered:
  - iOS does not expose every keyboard Settings state equally to the containing app and the keyboard extension.
  - Allow Full Access has scary system warning copy that cannot be hidden or softened by code.
  - Secure fields reject custom keyboards by platform design.
  - The custom keyboard may need a reset/reopen cycle after install, update, or Full Access changes.
  - Real transcription adds API, microphone permission, network, and state-timing failure modes beyond seeded transcripts.
  - The local Groq/Grok key must never be printed, committed, or echoed into logs.
  - Messages testing requires a safe self/test thread from the operator.
  - Prototype diagnostics should not quietly become polished production UI unless intentionally designed.

## Goal Oracle

The oracle for this goal is:

`On codex/ios-keyboard-prototype, a physical iPhone-preview walkthrough proves that onboarding and health/recovery UX can take Foil from unconfigured or unhealthy keyboard state to a successful real transcript insertion, with copied App Group state idle/no transcript afterward.`

The PM must keep comparing receipts to this oracle. A pretty checklist, a simulator run, or a passing seeded transcript is not enough if Full Access detection or the real record/transcribe/insert loop is not proved on the physical phone.

## Goal Kind

`specific`

## Current Tranche

Design and implement the smallest product-quality onboarding/recovery path around the custom keyboard architecture, then prove it with physical-device workflows.

## Conveyor Plan

1. **Scout Current UX And Constraints**: map the current iOS app, keyboard, diagnostics, prior receipts, and iOS Settings behavior relevant to keyboard install/Full Access.
2. **Judge Product Scope**: choose the smallest shippable onboarding/recovery surface and decide what remains debug-only.
3. **Onboarding Worker**: implement app-first onboarding for enabling Foil Keyboard and Allow Full Access, including plain-language system-warning context.
4. **Health/Recovery Worker**: implement health indicators and app-side reset/recovery controls that do not expose transcript text unnecessarily.
5. **Keyboard Guard Worker**: refine the keyboard-side unhealthy state, stale-state blocking, and return-to-app affordances.
6. **Real Loop Worker**: prove microphone permission, recording, Groq transcription, return to keyboard, insertion, and post-insert reset on the physical iPhone.
7. **Matrix Completion Worker**: rerun core rows plus Messages only if a safe thread is available.
8. **Judge Product Decision**: decide whether the Whisperflow-style app/keyboard cycle is acceptable for the next prototype, and name the next interaction slice.
9. **Issue/PR Handoff**: update issue #216 or create follow-up issues, open/merge PRs into `codex/ios-keyboard-prototype`, and preserve evidence.
10. **Final Audit**: try to disprove onboarding with Full Access off, stale App Group state, secure-field rejection, and real transcription failures before declaring completion.

Potential child boards:

- `ios-keyboard-settings-deep-link-research`: only if iOS Settings navigation needs separate research/prototyping.
- `ios-real-transcription-loop`: only if recording/transcription timing becomes large enough to deserve its own board.
- `ios-keyboard-polish-debug-ui`: only if diagnostic UI removal/polish expands beyond this slice.

## Non-Negotiable Constraints

- Do not merge this prototype directly to `main`.
- Do not commit API keys, private accessibility trees, Messages content, contacts, personal Reminders, sensitive screenshots, or raw recordings.
- Treat Allow Full Access as required for this architecture unless a Judge explicitly changes the architecture.
- Treat secure-field rejection as expected platform behavior and provide a fallback story rather than trying to bypass it.
- Physical-device proof is required for completion; simulator proof can only support implementation.
- Respect unrelated worktree changes and do not revert them.
- Use `docs/acceptance-evidence.md`: name the claim, strongest realistic failure mode, evidence, and residual risk.

## Stop Rule

Stop only when a final audit proves the oracle or records a narrow blocker with no remaining safe local work.

Do not stop after adding onboarding screens, after a seeded transcript insert, or after a single manual Settings walkthrough. The physical phone must prove configuration detection, recovery, real transcription, insertion, and post-insert reset.

## Canonical Board

Machine truth lives at:

`docs/goals/ios-keyboard-onboarding-full-access-ux/state.yaml`

If this charter and `state.yaml` disagree, `state.yaml` wins for task status, active task, receipts, verification freshness, and completion truth.

## Run Command

```text
/goal Follow docs/goals/ios-keyboard-onboarding-full-access-ux/goal.md.
```

## PM Loop

On every `/goal` continuation:

1. Read this charter.
2. Read `state.yaml`.
3. Re-check the oracle and the known Full Access/stale App Group failure mode.
4. Work only on the active task.
5. Assign Scout, Judge, Worker, or PM according to the task.
6. Write a compact receipt under the task and, when useful, a longer note under `notes/`.
7. Update the board.
8. Run the strongest realistic proof before claiming a task is done.
9. Create issue/PR handoff artifacts only when authorized by the active task.
10. Finish only with a final audit receipt that records `full_outcome_complete: true` or a precise blocker.
