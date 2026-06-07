# Foil iOS v0.22 TestFlight Release Proof

## Original Request

Continue the iOS prototype toward a usable iPhone preview build.

## Outcome

Package the v0.18-v0.21 tranche into a new TestFlight build and prove the
installed preview-phone build passes the core live transcription and keyboard
insertion smoke.

## Oracle

This board is complete only when:

- The iOS app and keyboard build number is bumped from source.
- The project is regenerated if needed.
- Archive, export, validation, upload, export-compliance, and internal tester
  attachment succeed.
- TestFlight installs or updates the preview phone to the new build.
- Device metadata confirms the installed build number.
- A physical smoke proves live transcription and exact-once keyboard insertion
  on the installed TestFlight build.
- Final scans prove no credentials, raw private phone content, or generated
  sensitive receipts were committed.

## Non-Goals

- Do not pursue App Store external review in this board.
- Do not add new host-app rows unless needed to prove the release smoke.
- Do not delete user data or TestFlight installs without operator approval.

## Seed Plan

1. Scout current build metadata, merged PRs, and outstanding v0.18-v0.21
   receipts.
2. Judge whether the tranche is release-ready or needs one fix first.
3. Produce/upload/attach the next TestFlight build.
4. Install/update on the preview iPhone and run the smoke.
5. Audit the strongest failure mode: validating a debug/local build while
   claiming the TestFlight build is proven.

## Starter Command

`/goal Follow docs/goals/ios-v0.22-testflight-release-proof/goal.md.`
