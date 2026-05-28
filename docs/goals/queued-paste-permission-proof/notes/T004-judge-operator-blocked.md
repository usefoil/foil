# T004 Judge: Operator Blocked

## Decision

operator_blocked

## Outcome

`full_outcome_complete: false`

## Rationale

T003 completed the local portions that can be done safely:

- local signing setup;
- signed install to `/Applications/Foil.app`;
- installed app identity precheck;
- guided System Settings launch.

The same external blocker remains: Foil diagnostics report
`SetupHealth: accessibilityTrusted=false`. Running the queued-paste smoke now
would repeat the known invalid condition rather than prove the goal oracle.

This is not a product-fix condition yet. Product-code scope should only open if
Foil reports `accessibilityTrusted=true` and TextEdit/Chrome queued delivery
still fails.

## Resume Condition

Resume the smoke Worker only after:

1. Accessibility is refreshed for `/Applications/Foil.app`.
2. Input Monitoring is refreshed if Foil appears there.
3. Foil is quit and reopened.
4. Diagnostics show `SetupHealth: accessibilityTrusted=true`.
