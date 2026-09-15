# Mac Mini Deterministic Merge Gate Design

**Date:** 2026-09-15  
**Status:** Approved design; implementation not started

## Summary

Foil will use three dedicated Mac minis as an interchangeable, repository-scoped GitHub Actions runner pool. When GitHub creates a `merge_group` commit at the front of the merge queue, the pool will run the complete deterministic macOS UI suite in three concurrent shards. A single stable required check, `Foil Deterministic UI Gate`, will report the aggregate result.

The initial performance objective is a median end-to-end duration under ten minutes with a hard timeout of fifteen minutes. Test failures will not retry. Recoverable infrastructure failures may receive one cleanup and retry on the same runner. The design explicitly excludes Codex Computer Use, exploratory QA, live network providers, real microphone input, and other nondeterministic checks.

## Current State

Foil already has the main ingredients for this system:

- GitHub merge-queue workflows using the `merge_group` event.
- A repository-scoped self-hosted macOS E2E workflow.
- Eighty-five `FoilUITests` test methods at the time of this design.
- Deterministic seeded UI states and a local fixture-transcription E2E path.
- Stable local signing support and separate production/development identities.
- Runner cleanup and healthcheck conventions.
- `.xcresult`, log, screenshot, and summary artifact patterns.

The current runner fleet is inconsistent:

| Host | Foil runner state | macOS | Xcode |
| --- | --- | --- | --- |
| `mm1` / Jeremy's Mac mini (1) | Stale `mac-mini-1` service repeatedly failing to connect | 26.3.1 | 26.3 |
| `mm2` / Jeremy's Mac mini (2) | Active `foil-mac-mini-2`, but labels do not match the checked-in workflow | 26.2 | 26.6 |
| `mm3` / Jeremy's Mac mini (3) | No Foil runner; an unrelated organization runner exists | 26.5.2 | 26.3 |

Historical full UI diagnostics took approximately fourteen minutes on one GitHub-hosted Mac. Three-way sharding makes the ten-minute objective plausible, but the target must be validated with current hardware and test timings.

## Goals

1. Exercise every deterministic Foil macOS UI test at the tip of the merge queue.
2. Run the suite concurrently across all three Mac minis without machine-specific scheduling.
3. Produce one stable required status check for GitHub branch protection and merge queues.
4. Fail clearly on test failures, missing coverage, runner unavailability, or machine drift.
5. Preserve complete diagnostic evidence for failures.
6. Keep setup and maintenance small enough for a single developer to operate.
7. Reach a median completion time under ten minutes without weakening coverage.

## Non-Goals

This design does not include:

- Codex Remote or Computer Use.
- LLM-driven visual review or exploratory testing.
- Live Groq, OpenAI, or other external provider checks.
- Real microphone capture.
- Real paste delivery into third-party applications.
- Destructive manipulation of the macOS TCC database.
- Notarized DMG, Homebrew installation, or release-signing validation.
- A custom scheduler, shared build server, virtual-machine layer, or third-party Mac CI platform.
- Immediate replacement of existing GitHub-hosted build, unit, snapshot, or focused PR smoke jobs.

The excluded checks remain available as named manual or scheduled workflows. They must not appear as silent skips inside the deterministic required gate.

## Architecture

GitHub Actions is the sole orchestration layer. Each mini runs one Foil repository-scoped Actions runner from the logged-in graphical test account. All runners advertise the same scheduling capability:

```text
self-hosted, macOS, ARM64, foil-deterministic
```

Machine-specific labels such as `mm1`, `mm2`, and `mm3` may be retained for diagnostics, but merge-gate jobs must not select a specific host. Any shard must produce the same result on any mini.

The merge-gate workflow has four logical stages:

1. **Detect and enumerate:** determine whether the merge-group commit affects the app, enumerate the deterministic tests, and validate the shard manifest.
2. **Execute:** dispatch three matrix jobs with `max-parallel: 3` and `fail-fast: false` to the shared pool.
3. **Collect:** upload one result receipt and diagnostic artifact set from every shard, including failed shards.
4. **Aggregate:** run an `if: always()` GitHub-hosted job that downloads all receipts and publishes the single `Foil Deterministic UI Gate` conclusion.

Only one full merge gate may occupy the pool at a time. Additional merge-group runs wait rather than competing for runners. Runs are not silently canceled after testing starts.

## Runner Baseline

The initial pinned baseline is macOS 26.5.2 and Xcode 26.6. The exact macOS build number and Xcode build number are recorded in a version-controlled runner manifest. The pool does not follow a floating `latest` toolchain.

All three minis will:

- Use dedicated, non-admin test accounts with active graphical sessions.
- Run the Actions runner as a per-user LaunchAgent rather than a headless system daemon.
- Run no other GitHub Actions runner concurrently in the same graphical session; unrelated runner services are disabled reversibly while the host belongs to the Foil pool.
- Select the pinned Xcode explicitly with `DEVELOPER_DIR` or `xcode-select` established during bootstrap.
- Keep the graphical session and displays awake while available to CI.
- Disable automatic macOS and Xcode upgrades.
- Use stable Foil signing and bundle identities.
- Keep a bounded runner work directory and independently disposable DerivedData.
- Start the runner automatically after login and recover after reboot.

Operating-system and Xcode upgrades are performed deliberately across all three machines in one maintenance operation. The pinned manifest changes only after the upgraded pool passes the deterministic gate repeatedly.

## Bootstrap and Healthchecks

One version-controlled bootstrap command performs the privileged, infrequent setup steps: prerequisite installation, runner registration, LaunchAgent installation, directory creation, and toolchain selection. It is explicit and idempotent. CI jobs never invoke the mutating bootstrap path.

A separate preflight is read-only by default and runs at the start of every shard. It emits a JSON receipt and verifies:

- Expected architecture, macOS version/build, and Xcode version/build.
- Expected logged-in console user and availability of a graphical session.
- Developer Mode and required Xcode components.
- Foil runner identity, repository association, and scheduling labels.
- Minimum free disk space.
- Writable, correctly scoped runner and artifact directories.
- No stale Foil, FoilE2E, `xcodebuild`, or XCTest processes.
- No existing job lock or conflicting checkout.

Version drift, absent GUI state, or invalid runner configuration fails before a build begins. The failure is classified as infrastructure failure and included in the aggregate status.

## Deterministic Test Inventory

The required gate includes:

- Seeded-state `FoilUITests` flows.
- UI tests using deterministic launch arguments and reset defaults.
- Screenshot-producing UI assertions that do not depend on animation timing, external content, or host-specific appearance.
- The portable local fixture-transcription E2E path.

The inventory explicitly excludes live-provider, real-microphone, external-application, installed-release, and permission-prompt automation. The exclusion file contains a reason and owning workflow for every excluded test.

The workflow enumerates the built test bundle and compares it with two checked-in sets:

1. Tests assigned to shards.
2. Tests explicitly excluded from the deterministic gate.

The audit fails if a test is missing, duplicated, appears in both sets, or names a test that no longer exists. Adding a new UI test therefore requires an explicit classification before the merge gate can pass.

## Sharding and Execution

The initial shard manifest assigns every deterministic test to exactly one of three named shards. Assignments are static within a run and do not depend on which mini accepts the job.

Each shard performs:

1. Read-only preflight.
2. Narrow cleanup of stale Foil/XCTest processes and shard-owned temporary paths.
3. Repository checkout at the exact merge-group SHA.
4. `xcodebuild build-for-testing` with a shard-specific DerivedData path.
5. `xcodebuild test-without-building` with explicit `-only-testing` identifiers and a unique `.xcresult` path.
6. Result parsing, timing extraction, artifact collection, and receipt generation.
7. Narrow post-run cleanup under `if: always()`.

Each runner builds independently. The initial design intentionally avoids shared DerivedData, network caches, or transferring signed test products between machines. This costs some build time but keeps correctness and recovery simple. Shared build artifacts may be evaluated later only if measurements show that independent builds prevent the ten-minute target.

Per-test durations are retained as artifacts. After representative runs, the static manifest is rebalanced using measured durations rather than test counts. The checked-in manifest remains the source of truth, preserving reproducibility.

## Isolation and Cleanup

Each shard owns uniquely named DerivedData, result, log, and temporary directories derived from the workflow run ID, attempt, and shard name. Cleanup is constrained to those paths and known Foil test processes.

Jobs may reset Foil's deterministic test preferences and app-owned test data through supported launch arguments or scoped paths. Jobs must not:

- Reset the entire user account.
- Delete broad home, runner, Keychain, or Application Support directories.
- Modify the system TCC database.
- Remove unrelated GitHub runner installations.
- Reuse state from a previous shard as an input to correctness.

Running the same shard twice against the same commit must produce the same result regardless of its assigned mini or execution order.

## Result Receipts and Aggregation

Every shard writes a machine-readable receipt with at least:

- Workflow run ID, attempt, merge-group SHA, and shard name.
- Runner name, hostname, macOS build, Xcode build, and architecture.
- Enumerated test identifiers and executed test identifiers.
- Build start/end times and test start/end times.
- Passed, failed, skipped, and not-executed counts.
- Final classification: `passed`, `test_failed`, or `infra_failed`.
- Whether an infrastructure retry occurred and its reason.
- Paths or artifact names for `.xcresult`, logs, screenshots, and summaries.

The aggregator requires exactly one valid receipt for each shard. A missing, malformed, wrong-SHA, or incomplete receipt is an infrastructure failure. It fails the required check when:

- Any deterministic test fails.
- A test is skipped unexpectedly or not executed.
- Any shard remains infrastructure-failed after its permitted retry.
- The inventory audit fails.
- Receipts disagree on commit or pinned environment.

The aggregate summary identifies whether the blocking cause is product behavior, test behavior, or runner infrastructure. It links directly to the relevant artifacts.

## Retry and Flake Policy

Test failures never retry automatically. A passing retry would hide a flaky test and weaken confidence in the merge gate.

A shard may retry once on the same runner only when the first attempt proves that no test assertion failed, the retry can still complete inside the fifteen-minute workflow timeout, and the error is classified as recoverable infrastructure, such as:

- A known test process that the scoped cleanup could not terminate on its first attempt.
- A transient checkout or dependency-fetch failure.
- XCTest failing before the first test begins while still producing enough evidence to classify the failure.

Runner disappearance, persistent toolchain drift, missing GUI state, or repeated setup failure remains `infra_failed` and blocks the gate.

A flaky test may enter a visible quarantine only when it has:

- A documented failure signature.
- An owner.
- A linked repair issue.
- An expiry date.
- A separate non-blocking execution path that continues collecting evidence.

Quarantine is a temporary exception, not a retry mechanism or silent exclusion.

## Performance Objective

The initial service objectives are:

- Median end-to-end gate duration below ten minutes.
- Hard workflow timeout of fifteen minutes.
- All three shards begin promptly when the pool is healthy.
- Slowest-shard duration kept close to the other two through measured rebalancing.

Coverage is not reduced to meet the target. The first optimization order is:

1. Balance tests by observed duration.
2. Remove redundant setup and waits inside tests.
3. Reuse build work only within a single shard job.
4. Investigate safe cross-run or cross-machine build caching only with evidence that it is necessary.

## Rollout

### Phase 1: Standardize and register

- Upgrade all three minis to the pinned macOS and Xcode builds.
- Replace the stale `mm1` Foil registration.
- Retain and relabel the active `mm2` Foil runner.
- Disable the unrelated runner services on `mm2` and `mm3` without deleting their configuration, then add a Foil repository runner to `mm3`.
- Verify reboot recovery, logged-in GUI state, and health receipts.

### Phase 2: Build the non-blocking gate

- Add bootstrap, preflight, cleanup, inventory-audit, shard-runner, receipt, and aggregation scripts.
- Add the three-shard workflow for `workflow_dispatch` and non-required `merge_group` shadow runs.
- Preserve the existing GitHub-hosted CI and existing local E2E workflow until replacement evidence exists.

### Phase 3: Prove repeatability

- Run at least ten representative full-suite executions.
- Repeat the same commit consecutively.
- Rotate shard-to-machine assignments naturally through the shared runner label.
- Reboot each mini and verify automatic recovery.
- Inject a stale Foil process and verify scoped cleanup.
- Change the selected Xcode on one runner and verify preflight drift detection.
- Make one runner unavailable and verify a clear infrastructure result rather than a false success.
- Rebalance the manifest using collected durations.

### Phase 4: Enforce

- Require `Foil Deterministic UI Gate` for the merge queue.
- Retire or narrow superseded local E2E behavior only after the new gate proves equivalent or stronger.
- Document the one-command healthcheck and one maintenance procedure.

## Acceptance Criteria

The design is complete when all of the following evidence exists:

1. Three online repository-scoped runners share the `foil-deterministic` capability label.
2. All three report the same pinned architecture, macOS build, Xcode build, GUI state, and required tools.
3. The inventory audit accounts for every UI test exactly once as assigned or explicitly excluded.
4. Three shards execute the same merge-group SHA concurrently.
5. The aggregate check fails on a deliberate test assertion failure.
6. The aggregate check fails clearly on missing receipts, runner drift, and unresolved infrastructure failure.
7. No deterministic test failure is retried.
8. Failure runs preserve `.xcresult`, logs, screenshots, timings, and host receipts.
9. Repeated execution of the same commit produces identical results across changing runner assignments.
10. At least ten shadow runs complete without an unexplained flake or silent skip.
11. Median completion is under ten minutes, with no run exceeding the fifteen-minute timeout under healthy conditions.
12. All three runners recover and reconnect after reboot without manual repair.

## Security and Maintenance Boundaries

- Runners are scoped to the Foil repository rather than registered broadly for untrusted repositories.
- The deterministic self-hosted workflow runs only trusted merge-group commits for this repository; it does not run fork pull-request code with repository secrets.
- Test accounts are non-admin. Privileged bootstrap actions remain manual and explicit.
- Secrets required by excluded live-provider tests are not present in this deterministic workflow.
- Health receipts exclude credentials, tokens, private user data, transcript content, and broad environment dumps.
- Cleanup scripts validate every destructive target against the runner work directory or a known test-specific path.

Routine maintenance consists of reviewing health receipts, clearing bounded disk usage when alerted, and upgrading all three pinned environments together. A custom CI control plane is intentionally avoided.

## Deferred Work

After the deterministic merge gate is stable, a separate design may address remote Codex Computer Use and exploratory testing on the minis. That future tranche must not weaken, preempt, or silently share state with the required deterministic pool.
