# Queued Paste Permission Proof

## Objective

Complete the post-PR161 queued-paste compatibility proof by refreshing the installed app's macOS privacy consent, rerunning the real-target queued smoke, and deciding whether the next change is evidence-only or a product delivery fix.

## Original Request

Use `$goalbuddy:goal-prep` to plan the next step after PR 161: refresh permissions, rerun queued-paste smoke, and decide what comes next.

## Intake Summary

- Input shape: `specific`
- Audience: Foil users relying on queued paste to return text to the original app/window.
- Authority: `requested`
- Proof type: `test`
- Completion proof: A final audit maps the refreshed-permission run, queued smoke artifacts, and any PR/issue follow-up back to the oracle with `full_outcome_complete: true`.
- Goal oracle: With `/Applications/Foil.app` signed as `com.neonwatty.Foil` and Accessibility/Input Monitoring refreshed, `ALLOW_LOCAL_QA_SKIP=1 make test-queued-paste-compatibility` either passes TextEdit, Chrome, and unavailable-target fallback, or produces diagnostics proving a concrete product fix is needed and that fix is implemented or captured as the next approved PR.
- Likely misfire: Treating the local signing repair or generic Accessibility instructions as completion while never proving TextEdit/Chrome queued delivery under the corrected app identity.
- Blind spots considered:
  - macOS TCC consent is manual and cannot be silently granted by scripts.
  - A passing identity precheck is necessary but not sufficient; `SetupHealth: accessibilityTrusted=true` must be observed from the installed app.
  - If consent is refreshed and queued delivery still fails, the work becomes product behavior, not documentation.
  - Chrome state should not be damaged; the smoke must preserve the no-quit/no-active-tab-close safety from PR 161.
- Existing plan facts:
  - PR 161 merged at `5f901f5e59348cd45ada3b6a0e472d010c7c32b7`.
  - `scripts/setup-local-signing.sh` now repairs non-interactive codesign key access.
  - `/Applications/Foil.app` can be installed with `SIGN_IDENTITY="Foil Local Code Signing"` and pass `make prepare-local-permissions-qa-check`.
  - Latest PR 161 queued-smoke artifact was `/tmp/foil-queued-paste-compatibility-20260528-050432`.
  - TextEdit/Chrome queued delivery still failed while `SetupHealth: accessibilityTrusted=false`; unavailable-target fallback passed.

## Goal Oracle

The oracle for this goal is:

`After refreshing macOS privacy consent for the newly signed /Applications/Foil.app identity, the real-target queued-paste smoke either passes TextEdit, Chrome, and unavailable-target fallback, or produces trustworthy diagnostics that drive and verify a bounded product fix or explicit follow-up PR plan.`

The PM must keep comparing task receipts to this oracle. Planning, discovery, a passing identity precheck, or a local signing repair is not enough. The goal finishes only when a final Judge/PM audit maps receipts and verification back to this oracle and records `full_outcome_complete: true`.

## Goal Kind

`specific`

## Current Tranche

Refresh installed-app privacy consent, rerun the queued compatibility smoke, update evidence, and then choose the largest safe next slice:

- evidence-only closure if TextEdit, Chrome, and unavailable-target fallback pass;
- product fix if the app is trusted but queued delivery still fails;
- blocked receipt only if macOS privacy consent cannot be completed by the operator after documented guidance.

## Non-Negotiable Constraints

- Do not attempt to silently grant Accessibility, Input Monitoring, Microphone, or other TCC permissions.
- Do not mutate persistent user data or close the user's active Chrome tab.
- Do not add global queued-paste hotkey or overlapping transcription architecture in this tranche.
- Keep PR 161's local signing repair intact.
- Distinguish target app/window identity proof from clipboard-only success.
- Record exact commands, artifact paths, and Foil diagnostics for every smoke outcome.

## Stop Rule

Stop only when a final audit proves the full original outcome is complete.

Do not stop after planning, discovery, or Judge selection if a safe Worker task can be activated.

Do not stop after the permission refresh if the queued smoke remains red and diagnostics indicate a local product fix is possible.

Do not stop because a slice needs owner input for macOS privacy consent. Mark that exact slice blocked with a receipt, create the smallest safe follow-up, and continue all local, non-destructive work that can still move the goal toward the full outcome.

## Slice Sizing

Safe means bounded, explicit, verified, and reversible. It does not mean tiny.

A good task is the largest safe useful slice. For this goal, the first useful slice is the complete permission-refresh and smoke-rerun package, not one command at a time.

## Canonical Board

Machine truth lives at:

`docs/goals/queued-paste-permission-proof/state.yaml`

If this charter and `state.yaml` disagree, `state.yaml` wins for task status, active task, receipts, verification freshness, and completion truth.

## Run Command

```text
/goal Follow docs/goals/queued-paste-permission-proof/goal.md.
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
10. Review at phase, risk, rejected-verification, ambiguity, or final-completion boundaries.
11. Finish only with a Judge/PM audit receipt that maps receipts and verification back to the original user outcome and records `full_outcome_complete: true`.
