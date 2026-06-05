# Foil iOS TestFlight Build 3 Forward Proof

## Objective

Upload Foil iOS build `0.1.0 (3)`, attach it to internal TestFlight
immediately, install it over the currently installed TestFlight build `2` on
`iPhone-preview`, and rerun the shorter mailbox/audio/keyboard insertion smoke.

## Original Request

After build `2` was proven through TestFlight, the user asked to do the next
recommended tranche: create build `3`, prove the normal forward TestFlight
update path, and run the live smoke again.

## Intake Summary

- Input shape: `existing_plan`
- Audience: Foil owner/developer validating the iOS TestFlight release loop.
- Authority: `approved`
- Proof type: `demo`
- Completion proof: TestFlight exposes build `0.1.0 (3)` as the forward/latest
  install over build `2`, the preview phone installs build `3`, and the mailbox
  start/stop/transcribe plus Foil Keyboard insertion smoke passes.
- Goal oracle: physical-device receipts prove build `3` archive/export/upload,
  App Store Connect beta readiness/group attachment, TestFlight install/update
  over build `2`, `devicectl` installed metadata reporting bundle version `3`,
  and the live mailbox/audio/keyboard insertion loop against build `3`.
- Likely misfire: incrementing only the generated Xcode project or only uploading
  a build, while TestFlight still shows stale/older-build behavior or the phone
  continues running build `2`.

## Goal Oracle

The oracle for this board is:

`On codex/ios-testflight-build3-forward-proof, receipts prove or narrowly block
the forward TestFlight update from Foil iOS 0.1.0 build 2 to build 3 on
iPhone-preview, then prove the shorter live mailbox/audio/keyboard insertion
smoke on build 3.`

Simulator proof, App Store Connect upload alone, or a Debug install is not
enough.

## Current Tranche

Complete the build-3 forward-update loop:

1. Bump build metadata to `3` in source and generated Xcode project.
2. Archive/export/upload build `0.1.0 (3)`.
3. Set export compliance and attach build 3 to `Foil Internal Testers`.
4. Verify TestFlight presents build 3 as the current/latest path over build 2.
5. Install/update build 3 on `iPhone-preview`.
6. Rerun a short mailbox/audio/transcribe/insert/reset smoke.
7. PR the code and GoalBuddy receipts into `codex/ios-keyboard-prototype`.

## Non-Negotiable Constraints

- Do not commit API keys, JWTs, private keys, app-passwords, private
  accessibility trees, private transcripts, or private screenshots.
- Do not install a Debug build as substitute proof.
- Keep the Notes test field sterile.
- Respect unrelated worktree changes and do not revert them.
- Record if TestFlight still calls build 3 an older build or disables automatic
  updates.

## Canonical Board

Machine truth lives at:

`docs/goals/ios-testflight-build3-forward-proof/state.yaml`

## Run Command

```text
/goal Follow docs/goals/ios-testflight-build3-forward-proof/goal.md.
```

