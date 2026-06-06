# Foil iOS v0.15 Safari And Secure Field Matrix

## Original Request

Continue the iOS keyboard prototype conveyor after adding the sanitized WDA
evidence helper.

## Outcome

Run a privacy-safe physical iPhone-preview matrix on the current TestFlight build
for Safari/local textarea insertion and Safari/local secure-field rejection.

## Oracle

The board is complete when sanitized receipts prove:

- Safari/local textarea starts with Foil Keyboard visible and Insert latest
  enabled.
- Tapping Insert latest mutates the sterile textarea fixture and leaves Insert
  latest disabled.
- Focusing the sterile secure password field hides Foil Keyboard and leaves the
  pending transcript staged in App Group state.

## Constraints

- Do not commit raw WDA source, screenshots, transcript bodies, private URLs, or
  private app content.
- Use `scripts/ios-physical-wda-evidence.py` receipts as the source-controlled
  artifact shape.
- Keep Messages skipped unless a dedicated sterile self/test thread exists.
- Keep PRs targeted at `codex/ios-keyboard-prototype`.

## Proof Plan

1. Start WDA and the sterile Safari fixture server.
2. Stage a sterile fake transcript using Foil diagnostics.
3. Focus Safari/local textarea, record pre-insert receipt, insert, record
   post-insert receipt.
4. Stage a second sterile fake transcript, focus Safari/local password field,
   record secure-field rejection receipt plus App Group snapshot summary.
5. Stop WDA and the fixture server before handoff.

## Starter Command

`/goal Follow docs/goals/ios-v0.15-safari-secure-matrix/goal.md.`
