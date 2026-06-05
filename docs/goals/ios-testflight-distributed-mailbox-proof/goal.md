# Foil iOS TestFlight Distributed Mailbox Proof

## Objective

Prove the newly uploaded Foil iOS build `0.1.0 (2)` as a TestFlight-managed
install on `iPhone-preview`, then rerun the same physical-device mailbox,
speaker-audio transcription, and Foil Keyboard insertion loop that already
passed on the Debug-installed build.

## Original Request

The user asked to plan the next iOS build step with GoalBuddy Prep and then
start implementing. The immediate proof gap from the prior handoff is that the
preview phone had a Debug-installed build `2`; App Store Connect accepted the
TestFlight build, but the distributed install itself has not yet been proven.

## Intake Summary

- Input shape: `existing_plan`
- Audience: Foil owner/developer validating the iPhone TestFlight path.
- Authority: `approved`
- Proof type: `demo`
- Completion proof: `iPhone-preview` is running the TestFlight-managed build
  `0.1.0 (2)`, and receipts prove or narrowly block the mailbox command flow,
  live audio transcription, keyboard insertion into Notes, and shared-state
  reset on that distributed build.
- Goal oracle: a physical-device smoke transcript showing TestFlight build `2`
  installed from TestFlight, containing-app command mailbox start/stop/transcribe
  actions working, Mac speaker audio captured by the iPhone microphone and
  transcribed through Groq, and Foil Keyboard inserting that transcript into
  Notes through `textDocumentProxy.insertText`.
- Likely misfire: reusing the Debug-installed app proof and calling it a
  TestFlight proof, or deleting/reinstalling in a way that loses keyboard/app
  permissions without recording the recovery path.
- Blind spots considered: TestFlight processing/install availability, Debug app
  versus TestFlight app identity, keyboard enablement persistence across install
  source changes, App Group container reset semantics, WDA/tunnel reachability,
  AirPods or other audio routing capturing silence, private Notes content, and
  App Store Connect/API key secrecy.
- Existing plan facts: PR #238 already added the command mailbox, uploaded build
  `0.1.0 (2)`, and proved the Debug physical-device loop with Mac speaker audio.

## Goal Oracle

The oracle for this board is:

`On codex/ios-testflight-distributed-mailbox-proof, receipts prove or narrowly
block the same live mailbox/audio/keyboard insertion smoke against the
TestFlight-managed Foil iOS build 0.1.0 (2) on iPhone-preview.`

Planning, App Store Connect upload validation, simulator proof, Debug install
proof, or a TestFlight screen alone is not enough. The final audit must map the
distributed install and physical-device insertion evidence back to this oracle.

## Current Tranche

Complete the TestFlight distributed-install proof for the mailbox prototype.
Start with a read-only device/TestFlight reality check, choose the safest
install/update path, run the live proof loop, record receipts, and open a PR
back into `codex/ios-keyboard-prototype` with the board and any evidence docs.

## Conveyor Plan

1. **Reality Scout**: confirm branch state, TestFlight build availability,
   installed app source/version if observable, WDA/tunnel state, phone unlock
   state, and current audio route without changing app installs.
2. **Install Decision**: decide whether TestFlight can install/update over the
   Debug build, or whether deleting the Debug install requires user approval.
3. **Distributed Install Worker**: use TestFlight to install/update build `2`
   on `iPhone-preview`, preserving privacy and recording exact UI/device proof.
4. **Live Proof Worker**: rerun command mailbox start/stop/transcribe with Mac
   speaker audio and insert latest through Foil Keyboard into Notes.
5. **Handoff Worker**: record receipts, screenshot/log evidence, secret scan,
   and PR the proof artifacts into `codex/ios-keyboard-prototype`.
6. **Final Audit**: try to disprove that this was a TestFlight proof and record
   residual risk or completion.

Potential child boards:

- `ios-testflight-install-recovery`: only if TestFlight install/update becomes a
  multi-step blocker involving deletion, Apple ID state, or tester membership.
- `ios-keyboard-permission-retention`: only if TestFlight install resets or
  breaks keyboard/Open Access/App Group permissions and needs a dedicated matrix.

## Non-Negotiable Constraints

- Do not commit API keys, raw JWTs, private key paths beyond generic references,
  private transcripts, raw private accessibility trees, or private screenshots.
- Do not delete the current app install unless a task explicitly permits it or
  the user approves it after the Scout/Judge evidence says deletion is needed.
- Do not treat Debug build proof as TestFlight proof.
- Keep target-app testing privacy-safe; Notes must contain only sterile test
  content created for this smoke.
- Respect unrelated worktree changes and do not revert them.
- If the phone locks, disconnects, or TestFlight needs user action, record the
  exact blocker and keep doing safe local receipt/board work.

## Canonical Board

Machine truth lives at:

`docs/goals/ios-testflight-distributed-mailbox-proof/state.yaml`

If this charter and `state.yaml` disagree, `state.yaml` wins for task status,
active task, receipts, verification freshness, and completion truth.

## Run Command

```text
/goal Follow docs/goals/ios-testflight-distributed-mailbox-proof/goal.md.
```

