# Foil iOS v0.21 Keyboard UX Recovery

## Original Request

Keep going after the prototype insertion proof and reduce the practical friction
of using the custom keyboard.

## Outcome

Harden the keyboard recovery and status experience around the real-world reset
flow: switching away/back to Foil Keyboard, stale transcripts, disabled Insert
latest, provider failures, and cleanup after insertion.

## Oracle

This board is complete only when tests and physical receipts prove:

- The keyboard shows clear status for idle, recording/transcribing, complete,
  stale/error, and inserted states.
- Insert latest is enabled only when a usable transcript exists.
- Insert latest consumes the transcript exactly once.
- Stale or malformed App Group state does not enable duplicate/bad insertion.
- The app/keyboard gives the operator a recoverable path when iOS requires a
  keyboard refresh.

## Non-Goals

- Do not attempt to bypass iOS keyboard extension limitations.
- Do not add full settings/onboarding redesign beyond the recovery slice.
- Do not require private APIs.

## Seed Plan

1. Scout current keyboard UI/state handling and known friction from physical
   tests.
2. Judge the highest-value recovery slice.
3. Implement UI/state/test changes.
4. Verify in simulator and at least one physical sterile target.
5. Audit the strongest failure mode: the UI says insertion is available when
   the underlying App Group state is stale, consumed, or malformed.

## Starter Command

`/goal Follow docs/goals/ios-v0.21-keyboard-ux-recovery/goal.md.`
