# Foil iOS Target App Insertion Matrix v0.7

## Original Request

Continue iOS testing across real target apps.

## Outcome

Run a privacy-safe insertion matrix for Foil Keyboard across Notes, Safari/local web fixture, Reminders, secure fields, and Messages only if a safe self/test thread exists.

## Oracle

The matrix is true when every row has a sanitized pass/fail/blocker receipt proving keyboard visibility, Insert latest availability, target field mutation or expected rejection, and App Group reset/no-transcript state.

## Constraints

- Do not use private app content as evidence.
- Messages is skipped unless a dedicated safe self/test thread exists.
- Secure fields should prove the platform rejection path, not work around it.

## Starter Command

`/goal Follow docs/goals/ios-target-app-insertion-matrix-v0.7/goal.md.`
