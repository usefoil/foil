# Release Runner Contract

This is the provisional, shadow-only contract for the dedicated Foil Mac pool. It does not authorize a release, configure a runner, or make either workflow a required check. Promotion requires reviewed runtime receipts and a separate publication-binding change.

## Expected runner set

Every readiness evaluation requires exactly one fresh receipt from each of `foil-mm1`, `foil-mm2`, and `foil-mm3`. Runner names, host identities, and runner-service identities must all be unique. Missing, duplicate, stale, malformed, skipped, cancelled, or infrastructure-failed receipts fail closed.

All three machines are provisionally mandatory deterministic slots. Pending capability proof, `foil-mm3` is preferred for full UI, `foil-mm2` for installed/public-artifact, paste, managed-local, and onboarding checks, and `foil-mm1` for microphone and provider checks. These preferences are not routing guarantees or proof that the specialized capabilities exist. Current evidence supports only the observed arm64 macOS 27 fleet; it makes no Intel or broader macOS support claim.

Named ownership, incident responsibility, isolated account approval, and an unambiguous mm2 routing mechanism remain operator decisions. This contract must not be used to infer them.

## Readiness receipt

`Foil Release Runner Readiness (Shadow)` is manually dispatched and uses the shared deterministic label set. Its three jobs must become active on three distinct GitHub runner IDs before collecting evidence. Each job runs the existing read-only preflight and emits schema version 1 with:

- workflow SHA, run ID, attempt, observation time, and runner name;
- the allowlisted preflight facts only: runner/host identity, OS and toolchain versions, architecture, console-user category, lock/developer-mode state, free space, and active runner-service identity;
- classification `passed`, `skipped`, `cancelled`, or `infrastructure_failed`;
- cleanup status for a workflow-owned directory; and
- claim policy `shadow_advisory`.

Receipts never contain raw environment dumps, provider credentials, signing or keychain material, personal audio or transcript content, or user-document paths. The aggregate accepts only `passed` receipts from the exact expected set, same SHA/run/attempt, no more than 15 minutes old, with healthy preflights and successful cleanup.

## Bounded cleanup

Readiness cleanup may remove only a directory named `<run-id>-<attempt>-<slot>` immediately under `foil-readiness-runs`. The directory must contain exactly one matching ownership marker. Unknown content causes cleanup to stop; cleanup does not terminate processes or touch applications, user documents, TCC, credentials, keychains, runner services, or runner labels.

The deterministic UI executor retains its existing separately tested cleanup contract. It reuses this document's exact runner-set constant during aggregation; readiness does not expand deterministic UI's mutation boundary.

## Claim policy

The future release gate requires exact candidate provenance, hosted checks, all three unique UI slots, full UI, installed identity/signing/notarization/launch, paste/focus, non-destructive permission behavior, microphone, supported providers, managed-local, fresh-user onboarding, cleanup, fail-closed aggregation, publication binding, and public-artifact verification.

Readiness and deterministic UI remain advisory shadow evidence. A skipped required claim never becomes a pass. Destructive TCC work and emergency waivers remain manual, explicitly approved, and auditable. Provider, microphone, installed-artifact, permission, paste, managed-local, onboarding, publication-binding, and public-artifact claims are not proven by this readiness workflow.

Runtime proof requires repeated authorized dispatches after this workflow exists on a dispatchable ref. Local contract tests prove only parsing, fail-closed behavior, bounded cleanup, and workflow structure.

## Local deterministic remediation record

Read-only evidence from shadow run `35370635011` classified shards A and B as infrastructure failures: test enumeration launched the UI runner and timed out while enabling automation mode. Shard C reached tests and reported two test-harness assertions: the cleanup pane waited for an identifier absent from the captured accessibility tree despite a stable cleanup control being present, and the delivered-state assertion read the preceding processing label before the asynchronous transition completed.

The local harness now validates the source manifest before building and no longer launches UI automation merely to enumerate tests. A successful build still proves the selected test source compiles, and post-run result-tree validation remains responsible for exact executed-test identity. The two UI assertions now use the observed stable cleanup control and wait for the delivered label transition. Contract tests reproduce all three failure modes without launching UI tests. This is local remediation only; no dispatch has proved the changes on a runner.
