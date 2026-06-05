# Foil iOS TestFlight Onboarding And Failure Recovery

## Objective

Turn the proven Foil iOS keyboard prototype into a TestFlight-ready first-run and recovery experience: a tester should be able to install the app, enable Foil Keyboard, understand Allow Full Access, grant microphone access, configure or provide transcription credentials safely, record/transcribe, return to the target app, insert once, and recover from common failure states without developer intervention.

## Original Request

The user asked to plan the next steps with GoalBuddy prep entirely and then begin.

## Intake Summary

- Input shape: `specific`
- Audience: Foil owner/developer preparing the iPhone prototype for early TestFlight testers.
- Authority: `approved`
- Proof type: `demo`
- Completion proof: PRs into `codex/ios-keyboard-prototype` prove a TestFlight-grade onboarding/failure-recovery slice with physical iPhone walkthrough evidence.
- Goal oracle: starting from a fresh or intentionally unhealthy iPhone state, a physical preview-device walkthrough proves the app guides keyboard install, Full Access, microphone permission, provider/key readiness, recording, transcription, return-to-keyboard, one-time insertion, and recovery/reset, with App Group state idle/no transcript afterward and no secrets/private target content committed.
- Likely misfire: polishing the prototype screen while leaving DEBUG-only key injection, unclear Full Access copy, unhandled transcription failures, or developer-only reset/testing controls in the normal tester path.
- Blind spots considered:
  - Apple's Full Access warning cannot be hidden and may scare testers.
  - DEBUG UserDefaults key injection is not a production/TestFlight provider-auth design.
  - Keyboard extensions cannot own every microphone/provider interaction reliably.
  - Secure fields and some target apps reject custom keyboards by platform design.
  - App/keyboard handoff may require switch-away/switch-back recovery after install, update, or Full Access changes.
  - Messages support cannot be claimed until a safe self/test thread is available.
  - WDA/target-app source can expose private content; evidence must be sanitized.
  - Raw recordings, transcripts, and API keys must not be committed or logged.

## Goal Oracle

The oracle for this goal is:

`On codex/ios-keyboard-prototype, a physical iPhone-preview walkthrough proves a fresh TestFlight-style tester can complete setup, provider readiness, microphone recording, transcription, keyboard insertion, and recovery from common failure states, with copied App Group state idle/no transcript afterward and sanitized issue/PR evidence.`

The PM must keep comparing every task receipt to this oracle. A clean build, a pretty checklist, or simulator-only proof is not enough.

## Goal Kind

`specific`

## Current Tranche

Replace prototype-only iOS controls and hidden developer assumptions with a tester-facing setup, credential, permission, and recovery path, while preserving the proven custom-keyboard architecture.

## Conveyor Plan

1. **Scout Current Prototype And Evidence**: map current app/keyboard UI, diagnostics, provider/key path, permission handling, previous receipts, branch status, and physical-device availability.
2. **Judge TestFlight Slice**: choose the smallest TestFlight-grade slice that moves beyond prototype controls without overbuilding account/history/provider settings.
3. **First-Run Setup Worker**: implement a tester-facing setup checklist/health surface for keyboard install, Full Access, microphone permission, and shared-state readiness.
4. **Provider Credential Worker**: replace local DEBUG-only key injection for testers with a safe internal-TestFlight credential path, likely Keychain-backed key entry/clear status, without exposing values.
5. **Failure Recovery Worker**: implement visible states and controls for missing key, microphone denied, network/API failure, empty transcript, stale transcript, and reset/retry.
6. **Return-To-Keyboard Worker**: improve the app/keyboard handoff copy and state transitions around recording, processing, transcript ready, and insert/reset.
7. **Messages Fixture Worker**: establish a safe Messages self/test thread or record a narrow blocker; do not inspect private threads.
8. **Physical Matrix Worker**: rerun Notes, Safari, Reminders, Messages if safe, secure-field rejection, and at least one failure-state recovery on the physical phone.
9. **TestFlight Readiness Judge**: audit entitlements, app group, keyboard extension settings, background audio, privacy strings, and tester runbook readiness.
10. **Issue/PR Handoff Worker**: update issue #216 or create follow-ups, open and merge PRs into `codex/ios-keyboard-prototype`, and preserve sanitized evidence.
11. **Final Audit**: try to disprove the TestFlight readiness oracle before marking the board done.

Potential child boards:

- `ios-provider-credential-hardening`: if credential storage grows beyond internal key entry.
- `ios-keyboard-messages-fixture`: if Messages testing requires dedicated setup.
- `ios-testflight-release-config`: if signing/TestFlight packaging becomes larger than this UI/recovery slice.

## Non-Negotiable Constraints

- Do not merge this prototype directly to `main`.
- Do not commit API keys, raw recordings, full private accessibility trees, Messages content, contacts, personal Reminders, private Notes, or sensitive screenshots.
- Treat Allow Full Access as required for the current architecture unless a Judge explicitly changes the architecture.
- Treat secure-field rejection as expected platform behavior and provide fallback copy rather than trying to bypass it.
- Physical-device proof is required for completion; simulator proof can support implementation but cannot close the board.
- Production/TestFlight credential handling must not rely on printed shell env vars, process arguments, or DEBUG-only hidden injection as the tester story.
- Respect unrelated worktree changes and do not revert them.
- Use `docs/acceptance-evidence.md`: name the claim, strongest realistic failure mode, evidence, and residual risk.

## Stop Rule

Stop only when a final audit proves the oracle or records a narrow blocker with no remaining safe local work.

Do not stop after building a checklist, after a single happy-path insert, or after proving only seeded transcripts. The physical phone must prove setup, credential readiness, microphone/transcription failure handling, insertion, and reset/recovery with sanitized evidence.

## Canonical Board

Machine truth lives at:

`docs/goals/ios-testflight-onboarding-failure-recovery/state.yaml`

If this charter and `state.yaml` disagree, `state.yaml` wins for task status, active task, receipts, verification freshness, and completion truth.

## Run Command

```text
/goal Follow docs/goals/ios-testflight-onboarding-failure-recovery/goal.md.
```

## PM Loop

On every `/goal` continuation:

1. Read this charter.
2. Read `state.yaml`.
3. Re-check the TestFlight oracle and the known key/permission/Full Access failure modes.
4. Work only on the active task.
5. Assign Scout, Judge, Worker, or PM according to the task.
6. Write a compact receipt under the task and, when useful, a longer note under `notes/`.
7. Update the board.
8. Run the strongest realistic proof before claiming a task is done.
9. Create issue/PR handoff artifacts only when authorized by the active task.
10. Finish only with a final audit receipt that records `full_outcome_complete: true` or a precise blocker.
