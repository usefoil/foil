# Foil iOS v0.8 TestFlight Build 8

## Original Request

Ship the v0.8 recovery improvements to TestFlight as build 8 and smoke them on the preview iPhone.

## Outcome

Foil iOS build `0.1.0 (8)` is built from the current v0.8 prototype branch, uploaded to App Store Connect/TestFlight, attached to `Foil Internal Testers`, installed or exactly blocked on `iPhone-preview`, and smoke-tested without private content.

## Oracle

The release tranche is true when source/project/IPA/App Store Connect/iPhone-preview all agree on build 8, simulator tests pass, the uploaded build is valid and available to internal testers, and the preview-phone smoke either passes or records an exact external blocker.

## Constraints

- Do not print, commit, or include App Store Connect private keys, JWTs, Groq keys, or private phone content.
- Do not test Messages unless a sterile self/test thread exists.
- Keep the PR target `codex/ios-keyboard-prototype`.
- Record physical smoke evidence using sanitized state/copy only.

## Starter Command

`/goal Follow docs/goals/ios-v0.8-testflight-build8/goal.md.`
