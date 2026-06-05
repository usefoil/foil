# Foil iOS TestFlight Build 4 Update Hygiene

## Objective

Prove the TestFlight release loop remains healthy after build `3` by uploading
build `0.1.0 (4)`, installing it over build `3`, recording the Automatic Updates
state, and running a minimal build-4 live smoke.

## Original Request

The user asked to immediately do the recommended next step after build `3`: a
short GoalBuddy board for build-4 update hygiene, followed by preparing the
larger iOS UX v0.2 board.

## Goal Oracle

`On codex/ios-testflight-build4-update-hygiene, receipts prove or narrowly block
a clean TestFlight update from Foil iOS build 3 to build 4 on iPhone-preview,
including Automatic Updates state, devicectl build-4 metadata, and a minimal
live mailbox/audio/keyboard insertion smoke.`

## Current Tranche

1. Bump build metadata to `4` from `FoiliOS/project.yml`.
2. Archive/export/upload build `0.1.0 (4)`.
3. Clear export compliance and attach build 4 to `Foil Internal Testers`.
4. Inspect TestFlight for Automatic Updates and build-4 update presentation.
5. Install/update build 4 over build 3 and verify metadata.
6. Run a minimal live mailbox/audio/keyboard insertion smoke.
7. PR/merge the proof artifacts into `codex/ios-keyboard-prototype`.
8. Seed the follow-up iOS UX v0.2 board.

## Constraints

- Do not commit API keys, JWTs, private keys, private screenshots, raw private
  accessibility trees, or private transcripts.
- Do not use a Debug install as substitute proof.
- Keep Notes content sterile.
- Respect unrelated untracked Xcode user data and marketing-plan files.
- Record Automatic Updates state honestly; do not hide if it remains off.

## Canonical Board

Machine truth lives at:

`docs/goals/ios-testflight-build4-update-hygiene/state.yaml`

## Run Command

```text
/goal Follow docs/goals/ios-testflight-build4-update-hygiene/goal.md.
```

