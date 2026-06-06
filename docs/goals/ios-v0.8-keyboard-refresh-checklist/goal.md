# Foil iOS v0.8 Keyboard Refresh Checklist

## Original Request

Continue the iOS v0.8 keyboard-friction work after adding keyboard health recovery copy.

## Outcome

Give testers an explicit in-app checklist for recovering stale, unverified, or Full Access-off Foil Keyboard states.

## Oracle

The slice is true when recovery checklist steps are generated from deterministic presenter state, shown in the app recovery surface only when useful, covered by tests, and do not imply Messages or secure-field support.

## Constraints

- No Messages testing or private app inspection.
- No TestFlight upload/build bump in this slice.
- Keep checklist copy concise enough for iPhone screens.
- Prefer pure presenter tests over fragile UI automation for the first implementation.

## Starter Command

`/goal Follow docs/goals/ios-v0.8-keyboard-refresh-checklist/goal.md.`
