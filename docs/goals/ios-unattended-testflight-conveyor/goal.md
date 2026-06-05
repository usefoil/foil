# Foil iOS Unattended TestFlight Conveyor

## Intent

Run the next few hours of Foil iOS work as a controlled GoalBuddy conveyor: plan, investigate, implement, test, open PRs, record receipts, and keep choosing the next highest-value internal-TestFlight slice until a real blocker requires user/device/account input.

## Oracle

The conveyor is succeeding when each completed slice has a scoped branch/PR into `codex/ios-keyboard-prototype` or the active integration branch, a GoalBuddy receipt with proof from simulator and physical iPhone testing where applicable, no committed secrets/private content, and a final audit that names residual risk instead of hand-waving it away.

## Starting Context

- Continue from `/Users/neonwatty/Desktop/foil`.
- The current completed iOS recovery PR is `https://github.com/mean-weasel/foil/pull/229`.
- The prior board is `docs/goals/ios-testflight-onboarding-failure-recovery/`.
- Known residual risks include:
  - Messages needs a safe self/test thread before a meaningful target-app run.
  - TestFlight archive/export metadata needs verification before upload.
  - Provider credential entry is still internal key entry, not production auth.
  - Physical device testing depends on phone availability, WDA/tunnel state, unlock state, and app permissions.
- Do not print, store, or commit live API keys, transcript bodies, private app content, raw accessibility trees from private apps, or raw device screenshots with private content.

## Operating Rules

- Use one active task at a time.
- Prefer Scout/Judge before Worker when the next slice is ambiguous.
- Keep write scopes narrow and PR-sized.
- Create new branches with the `codex/` prefix.
- Open draft PRs unless the slice is fully verified and ready.
- Target `codex/ios-keyboard-prototype` or the current iOS integration branch, not `main`, unless a later receipt proves the branch policy changed.
- Do not revert unrelated user changes.
- Stop and record an exact blocker if physical phone, signing, GitHub auth, API key, or Apple account state prevents responsible progress.

## Starter Command

`/goal Follow docs/goals/ios-unattended-testflight-conveyor/goal.md.`
