# Agent Instructions

## Burden Of Proof

Before declaring work complete, try to disprove the change. Identify the
strongest realistic failure mode, verify it with a command, test, trace,
screenshot, audit record, diff, or direct inspection, and include that evidence
in the final handoff.

Treat `done`, `tests passed`, worker claims, passing happy-path tests, generated
summaries, and optimistic UI as claims, not proof. Treat unverified assumptions
as blockers or explicit follow-ups.

Use `docs/acceptance-evidence.md` to choose proof that matches the change. For
small docs or config edits, one strongest realistic failure mode may be enough.
For user-facing, release, permissions, paste, provider, or automation changes,
record the top realistic failure modes and the evidence that rules them out.
