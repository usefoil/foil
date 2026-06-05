# Foil iOS Build 7 Physical Smoke

## Original Request

Continue the iOS work by unblocking physical iPhone proof for the latest TestFlight-ready build.

## Outcome

Prove or precisely block build 7 on `iPhone-preview`: install/update, launch, capture sterile app/keyboard evidence, and verify App Group state without leaking private phone content.

## Oracle

Build 7 is physically true when the device reports Foil iOS build 7 or TestFlight-installed build 7, the app/keyboard loop is visible in a sterile target, and App Group state is sanitized and consistent after insert/reset.

## Constraints

- Use `docs/ios-physical-automation-runbook.md`.
- Do not commit raw WDA trees or screenshots from private apps.
- If WDA fails again, record lock state, status endpoint, exact command, exact error, process cleanup, and the fallback path.

## Starter Command

`/goal Follow docs/goals/ios-build7-physical-smoke/goal.md.`
