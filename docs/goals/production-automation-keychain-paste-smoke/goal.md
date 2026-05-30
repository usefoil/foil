# Production Automation Keychain Paste Smoke

## Objective

Fix and prove the production installed-app paste queue smoke so Foil automation does not let a macOS keychain prompt steal focus, diagnostics explain failures clearly, and the smoke produces trustworthy queued-paste compatibility evidence.

## Original Request

Plan the fix using GoalBuddy prep after three independent agents explored how to fix the SecurityAgent/keychain prompt blocker and whether logging exists.

## Intake Summary

- Input shape: `existing_plan`
- Audience: Foil maintainers and local production QA operators
- Authority: `approved`
- Proof type: `test`
- Completion proof: a verified local change set where focused unit/parse checks pass, the installed-app smoke either passes or fails fast with an explicit keychain/SecurityAgent diagnostic, and a final audit maps evidence back to the issue.
- Goal oracle: `make test-production-queued-paste-compatibility` against `/Applications/Foil.app`, plus focused Swift/Xcode verification for changed app logic.
- Likely misfire: only making the smoke skip or hide the prompt while leaving normal app launch vulnerable to surprise keychain UI, or declaring success from contaminated `SecurityAgent` target captures.
- Blind spots considered: normal user keychain repair behavior, installed-app automation representativeness, first-run onboarding focus, stale Keychain ACLs after signing/reinstall, and whether logs prove causal order.
- Existing plan facts:
  - Production app currently launches with `--automation-smoke`, not `--ui-testing`.
  - Setup health reads API-key state during launch and can trigger `SecurityAgent`.
  - Local logs already show keychain read timeout followed by `SecurityAgent` target capture.
  - App-side candidates are automation smoke API-key bypass, explicit non-interactive keychain reads, and improved keychain diagnostics.
  - Harness candidates are fail-fast `SecurityAgent` detection and stronger expected-frontmost assertions.

## Goal Oracle

The oracle for this goal is:

`make test-production-queued-paste-compatibility` produces trustworthy installed-app evidence: either TextEdit/browser queued-paste rows pass without `SecurityAgent`, or the smoke stops immediately with a clear keychain/SecurityAgent failure before target capture is contaminated.

The PM must keep comparing task receipts to this oracle. Planning, discovery, a passing tiny slice, or a clean-looking board is not enough. The goal finishes only when a final Judge/PM audit maps receipts and verification back to this oracle and records `full_outcome_complete: true`.

## Goal Kind

`existing_plan`

## Current Tranche

Validate the three-agent plan, implement the largest safe local slice that prevents `SecurityAgent` from corrupting production automation, improve diagnostics where needed, and verify with focused code checks plus the installed-app smoke path as far as macOS local permissions allow.

## Non-Negotiable Constraints

- Do not click, type into, or automate macOS keychain/security prompts.
- Preserve normal user behavior unless a change intentionally improves launch safety by avoiding surprise keychain UI.
- Do not hide real paste failures behind skips.
- The production compatibility smoke must fail fast when `SecurityAgent` owns focus.
- Keep edits scoped to app keychain/setup automation behavior, smoke harnesses, tests, and docs needed for this tranche.
- Do not revert unrelated user changes.

## Stop Rule

Stop only when a final audit proves the full original outcome is complete.

Do not stop after planning, discovery, or Judge selection if the user asked for working software or automation and a safe Worker task can be activated.

Do not stop after a single verified Worker package when the broader owner outcome still has safe local follow-up work. Advance the board to the next highest-leverage safe Worker package and continue unless a phase, risk, rejected-verification, ambiguity, or final-completion review is due.

Do not create one Worker/Judge pair per repeated file, table, route, or helper. Put repeated same-shape work into one Worker package and review the package as a whole.

## Slice Sizing

Safe means bounded, explicit, verified, and reversible. It does not mean tiny.

A good task is the largest safe useful slice.

Small is not the goal. Useful is the goal.

A Worker should finish the whole assigned slice. A Judge should judge the whole assigned slice. A PM should reorient the board when tasks are safe but not moving the outcome.

## Canonical Board

Machine truth lives at:

`docs/goals/production-automation-keychain-paste-smoke/state.yaml`

If this charter and `state.yaml` disagree, `state.yaml` wins for task status, active task, receipts, verification freshness, and completion truth.

## Run Command

```text
/goal Follow docs/goals/production-automation-keychain-paste-smoke/goal.md.
```

## PM Loop

On every `/goal` continuation:

1. Read this charter.
2. Read `state.yaml`.
3. Run the bundled GoalBuddy update checker when available and mention a newer version without blocking.
4. Re-check the intake: original request, input shape, authority, proof, blind spots, existing plan facts, and likely misfire.
5. Work only on the active board task.
6. Assign Scout, Judge, Worker, or PM according to the task.
7. Write a compact task receipt.
8. Update the board.
9. If safe local work remains, choose the next largest reversible Worker package and continue unless blocked.
10. Finish only with a Judge/PM audit receipt that maps receipts and verification back to the original user outcome and records `full_outcome_complete: true`.
