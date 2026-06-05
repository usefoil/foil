# iOS UX v0.6 Product Loop

## Original Request

Do the next iOS UX slice: make the record-return-insert loop feel like a product instead of a harness.

## Outcome

Foil iOS presents a clearer tester-facing loop across the containing app and keyboard: record in Foil, create the transcript, return to the target app, insert from Foil Keyboard, and recover cleanly from no-speech/failure states.

## Oracle

Focused tests must prove the core product-loop copy/states, simulator build/test checks must pass, and the final receipt must include visual or physical proof that the containing app and keyboard expose the clearer workflow.

## Constraints

- Keep the UX app-like and compact; do not add marketing/landing-page content.
- Use TDD for behavior/copy mapping that can be tested.
- Do not remove the diagnostic harness; keep it behind diagnostics/setup surfaces.
- Do not print or commit provider keys, App Store Connect keys, JWTs, or private phone content.
- Do not claim new audio-quality improvements unless physically proved.

## Likely Misfire

The UI could get prettier while still leaving testers unsure whether to record in the app, return to the keyboard, retry, or reset. The audit must verify the exact loop and recovery messages.

## Starter Command

`/goal Follow docs/goals/ios-ux-v0.6-product-loop/goal.md.`
