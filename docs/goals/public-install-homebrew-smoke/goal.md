# Public Install Homebrew Smoke

## Objective

Make Foil's public install path coherent now that the Homebrew tap is real and verified, then prove the public cask install path with a fresh-user smoke.

## Original Request

"ok plan this out with goalbuddy" after choosing the next step: update public install copy now that Homebrew is real and verified, then run a fresh-user public cask smoke.

## Intake Summary

- Input shape: `specific`
- Audience: prospective Foil beta users and release maintainers
- Authority: `requested`
- Proof type: `test`
- Completion proof: README, landing page, release docs, and release QA evidence consistently present the verified Homebrew path, and a fresh public cask install smoke proves Foil `1.12.2` installs, launches, and passes signing/Gatekeeper checks from the tap.
- Goal oracle: a repo/public-surface sweep plus a clean public cask install walkthrough that shows no stale "planned/unverified" Homebrew claims and records install/signing/version evidence.
- Likely misfire: updating a single README snippet while leaving the landing page, release docs, QA log, or actual install path stale or unverified.
- Blind spots considered: Homebrew tap naming can be confusing (`mean-weasel/foil` tap backed by `mean-weasel/homebrew-foil`); release docs may contain old cautious language; fresh-user smoke may touch `/Applications` or local TCC state if not isolated; the public release page and cask can drift from repo docs.
- Existing plan facts: Homebrew tap `mean-weasel/homebrew-foil` exists; cask `mean-weasel/foil/foil` was verified for Foil `1.12.2` build `34`; next desired work is public install copy alignment followed by a fresh-user smoke.

## Goal Oracle

The oracle for this goal is:

`A final repo and public-install walkthrough proves README, site, release docs, reference cask, and release QA evidence consistently name the verified Homebrew install path, and a clean public cask install smoke proves Foil 1.12.2 installs from mean-weasel/homebrew-foil with matching version/build, Gatekeeper acceptance, and deep codesign verification.`

The PM must keep comparing task receipts to this oracle. Planning, discovery, a nice-looking install snippet, or a successful cask install alone is not enough. The goal finishes only when a final Judge/PM audit maps receipts and verification back to this oracle and records `full_outcome_complete: true`.

## Goal Kind

`specific`

## Current Tranche

Discover the public install surfaces that mention Homebrew or release installation, update the largest safe coherent copy/docs package, verify the public cask path without mutating persistent user state when possible, record release QA evidence, and continue until the final audit proves public install messaging and install behavior are aligned.

## Non-Negotiable Constraints

- Do not create a new release unless a later task explicitly justifies and scopes it.
- Treat `mean-weasel/homebrew-foil` as the tap repository and `mean-weasel/foil` as the Homebrew tap alias.
- Prefer temp app directories for install smoke tests before touching `/Applications`.
- Do not wipe user TCC, Keychain, or existing `/Applications/Foil.app` state unless the user explicitly approves a destructive/fresh-machine simulation.
- Keep public copy accurate: Homebrew is verified for `1.12.2`, but macOS permissions and API-key setup still require user action.
- Record any external tap or release-page observations in task receipts; `state.yaml` remains board truth.

## Stop Rule

Stop only when a final audit proves the full original outcome is complete.

Do not stop after planning, discovery, or Judge selection if a safe Worker task can be activated.

Do not stop after a single verified Worker package when the broader owner outcome still has safe local follow-up work. Advance the board to the next highest-leverage safe Worker package and continue unless a phase, risk, rejected-verification, ambiguity, or final-completion review is due.

Do not stop because a slice needs owner input, credentials, production access, destructive operations, or policy decisions. Mark that exact slice blocked with a receipt, create the smallest safe follow-up or workaround task, and continue all local, non-destructive work that can still move the goal toward the full outcome.

## Slice Sizing

Safe means bounded, explicit, verified, and reversible. It does not mean tiny.

A good task is the largest safe useful slice.

Small is not the goal. Useful is the goal.

A Worker should finish the whole assigned slice. A Judge should judge the whole assigned slice. A PM should reorient the board when tasks are safe but not moving the outcome.

## Canonical Board

Machine truth lives at:

`docs/goals/public-install-homebrew-smoke/state.yaml`

If this charter and `state.yaml` disagree, `state.yaml` wins for task status, active task, receipts, verification freshness, and completion truth.

## Run Command

```text
/goal Follow docs/goals/public-install-homebrew-smoke/goal.md.
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
10. Review at phase, risk, rejected-verification, ambiguity, or final-completion boundaries; do not review every small Worker by habit.
11. Finish only with a Judge/PM audit receipt that maps receipts and verification back to the original user outcome and records `full_outcome_complete: true`.
