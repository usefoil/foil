# Foil iOS TestFlight Upload Readiness

## Intent

Determine whether this machine can validate or upload the current Foil iOS IPA to App Store Connect/TestFlight, and either perform the safest approved validation/upload step or record the exact account/tooling blocker and next human action.

## Oracle

The goal is complete when the repo has durable evidence for one of these outcomes:

- the current Foil iOS IPA was validated/uploaded with App Store Connect tooling and the command output/receipt is recorded without secrets; or
- validation/upload is blocked by a precise missing credential, account, provider, app record, Transporter, or Apple tool requirement.

This board must not confuse local archive/export proof with TestFlight upload proof.

## Starting Facts

- PR #230 proved a Release archive and App Store Connect style export.
- The exported IPA path from that board was `/tmp/FoilIOS-TestFlightReadinessExport/Foil iOS.ipa`, but `/tmp` artifacts may not persist between turns.
- `altool` is available through Xcode.
- `iTMSTransporter` reports that Transporter should be installed from the Mac App Store.
- No obvious App Store Connect environment variables or `~/.appstoreconnect/private_keys` files were found during the conveyor Scout.

## Non-Goals

- Do not print App Store Connect passwords, API private keys, JWTs, or keychain secret values.
- Do not upload to App Store Connect unless Judge explicitly approves it after Scout confirms credentials and artifact state.
- Do not change app behavior unless needed to satisfy an upload validation error.
- Do not test private Messages content.

## Starter Command

`/goal Follow docs/goals/ios-testflight-upload-readiness/goal.md.`
