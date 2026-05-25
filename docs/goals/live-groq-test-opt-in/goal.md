# Live Groq Test Opt-In

## Objective

Make GroqTalk's local and CI test workflow deterministic by ensuring live Groq API integration tests only run through an explicit opt-in target/path, while preserving a clear command for live provider verification when a valid key is intentionally supplied.

## Original Request

"make the live Groq integration tests opt-in even when a stale/invalid `GROQ_API_KEY` exists" and then "plan it out with `$goalbuddy:goal-prep`."

## Intake Summary

- Input shape: `specific`
- Audience: GroqTalk maintainers and beta-release operators
- Authority: `requested`
- Proof type: `test`
- Completion proof: deterministic local/unit and CI paths pass without requiring a live Groq API key, and an explicit live Groq test target/command remains documented and runnable with `RUN_LIVE_GROQ_TESTS=1 GROQ_API_KEY=...`.
- Goal oracle: `make test` or the repo's default unit-test command does not run live Groq network tests when the shell contains a stale or invalid `GROQ_API_KEY`; a separate live test command exists, is documented, and has focused verification.
- Likely misfire: merely documenting the caveat while leaving `make test` able to fail from stale live-test environment, or disabling live tests so thoroughly that intentional live-provider QA becomes unclear.
- Blind spots considered: CI may already avoid live tests; shell environment can still leak `RUN_LIVE_GROQ_TESTS=1`; Xcode test filtering may need Makefile-level or test-level hardening; docs should distinguish deterministic tests from release/live provider QA.
- Existing plan facts:
  - Desired split: `make test` runs deterministic non-live unit tests.
  - Desired split: `make test-live-groq` runs real Groq API integration tests explicitly.
  - CI should remain deterministic.
  - Docs should explain required `RUN_LIVE_GROQ_TESTS=1 GROQ_API_KEY=...` usage.

## Goal Oracle

The oracle for this goal is:

`Default test workflow passes without live Groq credentials, even in a shell that contains a stale or invalid GROQ_API_KEY, and a documented explicit live Groq command remains available for intentional provider verification.`

The PM must keep comparing task receipts to this oracle. Planning, discovery, a passing tiny slice, or a clean-looking board is not enough. The goal finishes only when a final Judge/PM audit maps receipts and verification back to this oracle and records `full_outcome_complete: true`.

## Goal Kind

`specific`

## Current Tranche

Complete the deterministic test split in one focused tranche: inspect the current Makefile, integration tests, and CI test invocation; choose the largest safe implementation slice; update test commands and docs; verify both deterministic and live-test command behavior; open/merge through the repo's normal PR and merge queue path if the implementation is safe.

## Non-Negotiable Constraints

- Do not remove live Groq integration coverage; make it explicit and intentional.
- Do not require valid Groq credentials for `make test`, CI unit tests, branch checks, or merge-queue checks.
- Do not leak API keys in logs, docs examples, or receipts.
- Preserve current release/open-beta workflow stability.
- Use the repo's existing Makefile, Xcode, and documentation patterns.
- Any implementation must go through verification before final audit.

## Stop Rule

Stop only when a final audit proves the full original outcome is complete.

Do not stop after planning, discovery, or Judge selection if the user asked for working software or automation and a safe Worker task can be activated.

Do not stop after a single verified Worker package when the broader owner outcome still has safe local follow-up work. Advance the board to the next highest-leverage safe Worker package and continue unless a phase, risk, rejected-verification, ambiguity, or final-completion review is due.

Do not create one Worker/Judge pair per repeated file, table, route, or helper. Put repeated same-shape work into one Worker package and review the package as a whole.

Do not stop because a slice needs owner input, credentials, production access, destructive operations, or policy decisions. Mark that exact slice blocked with a receipt, create the smallest safe follow-up or workaround task, and continue all local, non-destructive work that can still move the goal toward the full outcome.

## Slice Sizing

Safe means bounded, explicit, verified, and reversible. It does not mean tiny.

A good task is the largest safe useful slice.

Small is not the goal. Useful is the goal.

A Worker should finish the whole assigned slice. A Judge should judge the whole assigned slice. A PM should reorient the board when tasks are safe but not moving the outcome.

Tiny tasks are allowed when the failure is isolated, the risk is high, the scope is unknown, or the tiny task unlocks a larger slice. Tiny tasks are bad when they keep happening, do not change behavior, only add wrappers/contracts/proof files, or avoid the real milestone.

Do not stop because a slice needs owner input, credentials, production access, destructive operations, or policy decisions. Mark that exact slice blocked with a receipt, create the smallest safe follow-up or workaround task, and continue all local, non-destructive work that can still move the goal toward the full outcome.

## Canonical Board

Machine truth lives at:

`docs/goals/live-groq-test-opt-in/state.yaml`

If this charter and `state.yaml` disagree, `state.yaml` wins for task status, active task, receipts, verification freshness, and completion truth.

## Run Command

```text
/goal Follow docs/goals/live-groq-test-opt-in/goal.md.
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
10. If a problem, suggestion, or follow-up should become a repo artifact, create an approved issue/PR or ask the operator whether to create one.
11. Review at phase, risk, rejected-verification, ambiguity, or final-completion boundaries; do not review every small Worker by habit.
12. Finish only with a Judge/PM audit receipt that maps receipts and verification back to the original user outcome and records `full_outcome_complete: true`.

Issue and PR handoffs are supporting artifacts. `state.yaml` remains authoritative, and every external artifact decision must be recorded in a task receipt.
