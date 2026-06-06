# Foil iOS v0.14 Physical Evidence Harness

## Original Request

Continue the iOS keyboard prototype conveyor after v0.13 one-shot insertion
hardening.

## Outcome

Make future physical iPhone target-app checks repeatable by adding a sanitized
WDA evidence helper and updating the physical automation runbook to use it.

## Oracle

The board is complete when the repo contains a helper that can turn WDA source
JSON into a sanitized pass/fail receipt for target-app rows without printing raw
transcript or private app content. The helper must prove positive checks, fail
on wrong expectations, and support the post-insert keyboard state where Insert
latest remains present but disabled.

## Constraints

- Do not commit raw WDA trees, screenshots, transcript bodies, phone numbers,
  contacts, reminder titles, messages, or private URLs.
- Keep Messages skipped unless a dedicated sterile self/test thread exists.
- Prefer hashes, booleans, counts, and accessibility identifier state over raw
  host-app content.
- Keep PRs targeted at `codex/ios-keyboard-prototype`.

## Proof Plan

1. Add `scripts/ios-physical-wda-evidence.py`.
2. Update `docs/ios-physical-automation-runbook.md` with a concrete usage path.
3. Verify the helper against a synthetic WDA fixture.
4. Verify the helper against the v0.13 physical Notes build 10 receipt in `/tmp`.
5. Run a negative count expectation and prove it exits non-zero without leaking
   the raw phrase.

## Starter Command

`/goal Follow docs/goals/ios-v0.14-physical-evidence-harness/goal.md.`
