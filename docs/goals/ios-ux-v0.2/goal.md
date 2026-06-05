# Foil iOS UX v0.2

## Objective

Turn the proven iOS TestFlight keyboard prototype from a test-harness workflow
into a small, understandable v0.2 user experience for recording, transcribing,
recovering, and inserting text from the custom keyboard.

## Original Request

After proving the TestFlight update loop through build `4`, prepare the larger
iOS UX v0.2 board as the next product slice.

## Goal Oracle

`Foil iOS v0.2 has a coherent containing-app and keyboard UX that a tester can
use without understanding the mailbox test harness: clear record/stop/transcribe
states, keyboard insert/retry/recovery states, privacy-safe onboarding cues, and
physical-device smoke proof in Notes plus at least one additional target app.`

## Current Tranche

This board starts with read-only discovery. Implementation should follow only
after Scout/Judge define a bounded Worker package.

## Non-Goals

- Do not build a marketing page.
- Do not replace the mailbox internals unless the UX slice truly requires it.
- Do not expand to private Messages testing without a sterile test thread.
- Do not commit secrets, private screenshots, private transcripts, or raw private
  accessibility trees.

## Canonical Board

Machine truth lives at:

`docs/goals/ios-ux-v0.2/state.yaml`

## Run Command

```text
/goal Follow docs/goals/ios-ux-v0.2/goal.md.
```

