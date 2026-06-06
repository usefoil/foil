# Foil iOS v0.8 Keyboard Friction

## Original Request

Continue from the v0.7 conveyor, plan with GoalBuddy prep, and implement the next iOS slice.

## Outcome

Reduce internal TestFlight friction around Foil Keyboard refresh, Full Access, and stale shared state before broadening the target-app matrix again.

## Oracle

The v0.8 slice is true when the app and keyboard clearly tell a tester whether the keyboard has verified Full Access recently, whether the keyboard looks stale, what action to take next, and how to recover without guessing.

## Constraints

- Keep Messages out of scope until a sterile self/test thread exists.
- Do not upload a new TestFlight build unless product code changes justify it and build metadata is bumped deliberately.
- Do not commit private transcript bodies, App Store Connect secrets, API keys, JWTs, or private phone content.
- Prefer small PRs into `codex/ios-keyboard-prototype`.
- Physical proof is valuable, but deterministic tests must cover the first product-state slice before device testing.

## Starter Command

`/goal Follow docs/goals/ios-v0.8-keyboard-friction/goal.md.`
