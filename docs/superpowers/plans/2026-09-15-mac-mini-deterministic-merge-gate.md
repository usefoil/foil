# Mac Mini Deterministic Merge Gate Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a three-Mac-mini GitHub Actions pool that runs every deterministic Foil UI test at the tip of the merge queue and reports one trustworthy required check within a ten-minute median target.

**Architecture:** Three interchangeable repository-scoped runners share the `foil-deterministic` label. A `merge_group` workflow validates a checked-in test inventory, dispatches three static shards, captures one structured receipt per shard, and aggregates those receipts into `Foil Deterministic UI Gate`. Runner bootstrap is explicit and mutating; per-job preflight, cleanup, execution, and aggregation are deterministic and testable.

**Tech Stack:** GitHub Actions, Bash 3.2-compatible shell scripts, Node.js ESM and `node:test`, Xcode 26.6, `xcodebuild`, `xcresulttool`, GitHub CLI, macOS LaunchAgents.

**Spec:** `docs/superpowers/specs/2026-09-15-mac-mini-deterministic-merge-gate-design.md`

## Global Constraints

- Pin every runner to macOS 26.5.2 build 25F84 and Xcode 26.6 build 17F113 before enabling the pool.
- Schedule only repository-scoped runners carrying `self-hosted`, `macOS`, `ARM64`, and `foil-deterministic`.
- Keep all live provider, real microphone, cross-app paste, TCC mutation, notarized-install, Codex Computer Use, and exploratory checks outside this gate.
- Never retry a test assertion failure; retry only a classified pre-test infrastructure failure, once, when the retry can finish inside fifteen minutes.
- Never delete outside a validated run-owned directory or terminate an unrelated runner process.
- Disable unrelated runner services on `mm2` and `mm3` while those hosts belong to the Foil pool; retain their files for reversible restoration.
- Keep existing GitHub-hosted CI and local E2E workflows intact until shadow evidence justifies a separate retirement change.
- Do not make the aggregate check required until ten representative shadow runs satisfy the acceptance criteria.

## File Map

- `scripts/ci/runner-baseline.json`: pinned host facts and allowed Foil runner identities.
- `scripts/ci/ui-test-shards.json`: complete deterministic assignment, special fixture test, and explicit exclusions.
- `scripts/ci/ui-test-inventory.mjs`: discover test methods, seed selectors, and audit exact coverage.
- `scripts/ci/runner-preflight.mjs`: collect safe host facts and compare them with the pinned baseline.
- `scripts/ci/runner-cleanup.sh`: validate run-owned paths and terminate only known Foil test processes.
- `scripts/ci/shard-receipt.mjs`: turn build/test outcomes and `xcresulttool` summaries into a stable receipt.
- `scripts/ci/run-ui-shard.sh`: orchestrate preflight, build, ordinary XCUITests, fixture E2E, cleanup, and receipt creation.
- `scripts/ci/aggregate-ui-gate.mjs`: validate three receipts and emit the aggregate conclusion/summary.
- `scripts/ci/bootstrap-foil-runner.sh`: explicit idempotent runner registration and LaunchAgent setup.
- `scripts/ci/tests/*.test.mjs`: Node unit and contract tests for inventory, preflight, receipt, and aggregation.
- `scripts/ci/tests/test-runner-cleanup.sh`: destructive-boundary tests using temporary fixtures and dry-run mode.
- `scripts/ci/tests/test-run-ui-shard.sh`: orchestration tests using fake `xcodebuild`, `xcrun`, and fixture commands.
- `.github/workflows/macos-deterministic-ui-gate.yml`: shadow merge-group/workflow-dispatch pipeline.
- `Makefile`: focused commands for script tests, preflight, and one shard.
- `docs/macos-deterministic-runner-pool.md`: bootstrap, maintenance, failure classification, and enforcement runbook.

---

### Task 1: Deterministic Test Inventory and Shard Manifest

**Files:**
- Create: `scripts/ci/ui-test-inventory.mjs`
- Create: `scripts/ci/ui-test-shards.json`
- Create: `scripts/ci/tests/ui-test-inventory.test.mjs`

**Interfaces:**
- Consumes: `FoilUITests/FoilUITests.swift` test declarations.
- Produces: `discoverTests(source: string): string[]`, `discoverEnumeratedTests(enumeration: object): string[]`, `validateManifest(discovered: string[], manifest: object): string[]`, CLI commands `seed`, `check`, `check-built`, and `selectors --shard {a,b,c}`.

- [ ] **Step 1: Write failing inventory tests**

```javascript
import test from "node:test"
import assert from "node:assert/strict"
import { discoverEnumeratedTests, discoverTests, validateManifest } from "../ui-test-inventory.mjs"

test("discovers XCTest methods in source order", () => {
  const source = "func testAlpha() {}\n  func testBeta() throws {}\n"
  assert.deepEqual(discoverTests(source), ["testAlpha", "testBeta"])
})

test("normalizes Xcode JSON enumeration identifiers", () => {
  const enumeration = { values: [{ identifier: "FoilUITests/FoilUITests/testAlpha()" }] }
  assert.deepEqual(discoverEnumeratedTests(enumeration), ["testAlpha"])
})

test("rejects missing, duplicate, stale, and overlapping assignments", () => {
  const manifest = {
    schemaVersion: 1,
    suite: "FoilUITests/FoilUITests",
    shards: { a: ["testAlpha"], b: ["testAlpha"], c: ["testStale"] },
    specialTests: { testFixture: { shard: "c", command: "make test-fixture-transcription-e2e" } },
    excluded: { testFixture: { reason: "overlap", workflow: "fixture.yml" } }
  }
  assert.deepEqual(validateManifest(["testAlpha", "testBeta", "testFixture"], manifest), [
    "duplicate assignment: testAlpha",
    "overlapping assignment and exclusion: testFixture",
    "stale assignment: testStale",
    "unassigned test: testBeta"
  ])
})
```

- [ ] **Step 2: Run the tests and verify the missing-module failure**

Run: `node --test scripts/ci/tests/ui-test-inventory.test.mjs`

Expected: FAIL because `scripts/ci/ui-test-inventory.mjs` does not exist.

- [ ] **Step 3: Implement discovery, validation, seeding, and selector output**

```javascript
export function discoverTests(source) {
  return [...source.matchAll(/^\s*func\s+(test[A-Za-z0-9_]+)\s*\(/gm)].map(match => match[1])
}

export function discoverEnumeratedTests(enumeration) {
  const tests = []
  const visit = value => {
    if (Array.isArray(value)) return value.forEach(visit)
    if (!value || typeof value !== "object") return
    if (typeof value.identifier === "string") {
      const match = value.identifier.match(/^FoilUITests\/FoilUITests\/(test[A-Za-z0-9_]+)\(\)$/)
      if (match) tests.push(match[1])
    }
    Object.values(value).forEach(visit)
  }
  visit(enumeration)
  return [...new Set(tests)].sort()
}

export function validateManifest(discovered, manifest) {
  const assigned = Object.values(manifest.shards).flat()
  const special = Object.keys(manifest.specialTests)
  const excluded = Object.keys(manifest.excluded)
  const errors = []
  for (const name of new Set([...assigned, ...special])) {
    if ([...assigned, ...special].filter(item => item === name).length > 1) errors.push(`duplicate assignment: ${name}`)
    if (excluded.includes(name)) errors.push(`overlapping assignment and exclusion: ${name}`)
  }
  for (const name of [...assigned, ...special, ...excluded]) {
    if (!discovered.includes(name)) errors.push(`stale assignment: ${name}`)
  }
  for (const name of discovered) {
    if (![...assigned, ...special, ...excluded].includes(name)) errors.push(`unassigned test: ${name}`)
  }
  return [...new Set(errors)].sort()
}
```

The `seed` command must place `testLiveMicrophoneSmoke` in `excluded`, place `testE2ETranscription` in `specialTests` on shard `c`, and distribute all other tests round-robin across `a`, `b`, and `c`. It must refuse to overwrite an existing manifest. The `selectors` command prints one `-only-testing:FoilUITests/FoilUITests/${testName}` argument per ordinary test in the selected shard. `check-built` parses Xcode's JSON test enumeration and applies the same exact-coverage validation, making the built bundle authoritative in CI while the source scan remains the fast pre-build check.

- [ ] **Step 4: Generate and audit the initial manifest**

Run:

```bash
node scripts/ci/ui-test-inventory.mjs seed \
  --source FoilUITests/FoilUITests.swift \
  --manifest scripts/ci/ui-test-shards.json
node scripts/ci/ui-test-inventory.mjs check \
  --source FoilUITests/FoilUITests.swift \
  --manifest scripts/ci/ui-test-shards.json
```

Expected: `84 assigned, 1 excluded, 0 errors`; the only excluded test is `testLiveMicrophoneSmoke`, with `workflow` set to `.github/workflows/live-microphone-qa.yml`.

- [ ] **Step 5: Run the focused tests and commit**

```bash
node --test scripts/ci/tests/ui-test-inventory.test.mjs
git add scripts/ci/ui-test-inventory.mjs scripts/ci/ui-test-shards.json scripts/ci/tests/ui-test-inventory.test.mjs
git commit -m "test: define deterministic UI test inventory"
```

Expected: all inventory tests PASS and the manifest audit exits zero.

---

### Task 2: Pinned Runner Preflight

**Files:**
- Create: `scripts/ci/runner-baseline.json`
- Create: `scripts/ci/runner-preflight.mjs`
- Create: `scripts/ci/tests/runner-preflight.test.mjs`
- Create: `scripts/ci/tests/fixtures/healthy-runner.json`

**Interfaces:**
- Consumes: pinned JSON baseline plus safe host command output and GitHub runner environment variables.
- Produces: `compareFacts(baseline: object, facts: object): string[]` and CLI options `--baseline PATH --output PATH [--facts FIXTURE_PATH]`.

- [ ] **Step 1: Write failing comparison tests**

```javascript
import test from "node:test"
import assert from "node:assert/strict"
import { compareFacts } from "../runner-preflight.mjs"

const baseline = {
  architecture: "arm64", productVersion: "26.5.2", buildVersion: "25F84",
  xcodeVersion: "26.6", xcodeBuild: "17F113", minimumFreeBytes: 30_000_000_000,
  allowedRunnerNames: ["foil-mm1", "foil-mm2", "foil-mm3"],
  allowedConsoleUsers: ["neonwatty", "jeremywatt"]
}

test("accepts an exact healthy runner", () => {
  const facts = { ...baseline, runnerName: "foil-mm2", consoleUser: "jeremywatt",
    freeBytes: 40_000_000_000, developerModeEnabled: true, runnerOs: "macOS",
    runnerArch: "ARM64", activeRunnerServices: ["actions.runner.usefoil-foil.foil-mm2"] }
  assert.deepEqual(compareFacts(baseline, facts), [])
})

test("reports toolchain drift and competing services", () => {
  const facts = { architecture: "arm64", productVersion: "26.5.2", buildVersion: "25F84",
    xcodeVersion: "26.3", xcodeBuild: "17C529", runnerName: "foil-mm2",
    consoleUser: "jeremywatt", freeBytes: 40_000_000_000, developerModeEnabled: true,
    runnerOs: "macOS", runnerArch: "ARM64",
    activeRunnerServices: ["actions.runner.usefoil-foil.foil-mm2", "actions.runner.mean-weasel.mac-mini-2"] }
  assert.deepEqual(compareFacts(baseline, facts), [
    "active runner service count: expected 1, got 2",
    "xcodeBuild: expected 17F113, got 17C529",
    "xcodeVersion: expected 26.6, got 26.3"
  ])
})
```

- [ ] **Step 2: Verify the tests fail before implementation**

Run: `node --test scripts/ci/tests/runner-preflight.test.mjs`

Expected: FAIL because `compareFacts` is unavailable.

- [ ] **Step 3: Implement safe fact collection and comparison**

Collect only: hostname, `uname -m`, `sw_vers` version/build, `xcodebuild -version`, console user from `/dev/console`, `DevToolsSecurity -status`, free bytes for the runner work directory, `RUNNER_NAME`, `RUNNER_OS`, `RUNNER_ARCH`, and names from `launchctl list` matching `actions.runner.`. Never serialize environment variables, command lines, tokens, Keychain contents, or home-directory listings.

Write the receipt even on mismatch:

```json
{
  "schemaVersion": 1,
  "status": "healthy",
  "facts": {},
  "errors": []
}
```

Exit `0` when `errors` is empty and `2` when drift is present.

- [ ] **Step 4: Add the exact pinned baseline**

```json
{
  "schemaVersion": 1,
  "architecture": "arm64",
  "productVersion": "26.5.2",
  "buildVersion": "25F84",
  "xcodeVersion": "26.6",
  "xcodeBuild": "17F113",
  "minimumFreeBytes": 30000000000,
  "allowedRunnerNames": ["foil-mm1", "foil-mm2", "foil-mm3"],
  "allowedConsoleUsers": ["neonwatty", "jeremywatt"]
}
```

- [ ] **Step 5: Test with fixtures and commit**

```bash
node --test scripts/ci/tests/runner-preflight.test.mjs
node scripts/ci/runner-preflight.mjs --baseline scripts/ci/runner-baseline.json --facts scripts/ci/tests/fixtures/healthy-runner.json --output /tmp/foil-preflight.json
git add scripts/ci/runner-baseline.json scripts/ci/runner-preflight.mjs scripts/ci/tests/runner-preflight.test.mjs scripts/ci/tests/fixtures
git commit -m "ci: add pinned Mac runner preflight"
```

Expected: unit tests PASS and the healthy fixture exits zero.

---

### Task 3: Scoped Runner Cleanup

**Files:**
- Create: `scripts/ci/runner-cleanup.sh`
- Create: `scripts/ci/tests/test-runner-cleanup.sh`

**Interfaces:**
- Consumes: `--run-root`, `--workspace-root`, and `--mode before|after`; optional `FOIL_CI_DRY_RUN=1`.
- Produces: cleanup log lines and exit `0` only when every target is validated and known Foil processes are absent.

- [ ] **Step 1: Write failing path-boundary tests**

```bash
#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/../../.." && pwd)"
fixture_root="$(mktemp -d)"
trap 'rm -rf "$fixture_root"' EXIT
mkdir -p "$fixture_root/work/123-1-a"

FOIL_CI_DRY_RUN=1 "$repo_root/scripts/ci/runner-cleanup.sh" \
  --workspace-root "$fixture_root/work" --run-root "$fixture_root/work/123-1-a" --mode before

if FOIL_CI_DRY_RUN=1 "$repo_root/scripts/ci/runner-cleanup.sh" \
  --workspace-root "$fixture_root/work" --run-root "$fixture_root" --mode before; then
  echo "unsafe parent cleanup unexpectedly succeeded" >&2
  exit 1
fi
```

- [ ] **Step 2: Run the test and verify the missing-script failure**

Run: `bash scripts/ci/tests/test-runner-cleanup.sh`

Expected: FAIL because `runner-cleanup.sh` does not exist.

- [ ] **Step 3: Implement validated cleanup**

Resolve both paths with `cd ... && pwd -P`; require `run_root` to be a strict descendant of `workspace_root`; require the basename to match `^[0-9]+-[0-9]+-[abc]$`; refuse empty, `/`, home, or workspace-root targets. In `before` mode, terminate exact `Foil` and `FoilE2E` processes, and terminate an `xcodebuild`/`xctest` process only when its command line contains `Foil` and the validated workspace root. In `after` mode, remove only the validated run root. Dry-run mode prints actions without signaling or deleting.

- [ ] **Step 4: Exercise safe and unsafe cases**

Run:

```bash
bash scripts/ci/tests/test-runner-cleanup.sh
bash -n scripts/ci/runner-cleanup.sh scripts/ci/tests/test-runner-cleanup.sh
```

Expected: PASS; unsafe root, symlink escape, invalid basename, and empty-variable cases all fail without deleting fixtures.

- [ ] **Step 5: Commit**

```bash
git add scripts/ci/runner-cleanup.sh scripts/ci/tests/test-runner-cleanup.sh
git commit -m "ci: add scoped Mac runner cleanup"
```

---

### Task 4: Reuse the Shard Build for Fixture Transcription E2E

**Files:**
- Modify: `scripts/run-fixture-transcription-e2e-xcuitest.sh`
- Create: `scripts/ci/tests/test-fixture-e2e-build-reuse.sh`

**Interfaces:**
- Consumes: optional `XCTESTRUN_PATH`, `SKIP_BUILD_FOR_TESTING=1`, and `XCTEST_RESULT_BUNDLE_PATH`.
- Produces: the existing fixture assertions plus a dedicated fixture `.xcresult` without rebuilding when a validated `.xctestrun` is supplied.

- [ ] **Step 1: Write a failing fake-tool contract test**

Create fake `xcodebuild` and `PlistBuddy` executables in a temporary `PATH`. Invoke the script with `SKIP_BUILD_FOR_TESTING=1` and a fixture `.xctestrun`; assert the fake log contains `test-without-building` and `-resultBundlePath`, and does not contain `build-for-testing`.

```bash
SKIP_BUILD_FOR_TESTING=1 \
XCTESTRUN_PATH="$fixture_root/Foil.xctestrun" \
XCTEST_RESULT_BUNDLE_PATH="$fixture_root/fixture.xcresult" \
PATH="$fixture_root/bin:$PATH" \
bash scripts/run-fixture-transcription-e2e-xcuitest.sh
```

- [ ] **Step 2: Verify the test fails on the current unconditional build**

Run: `bash scripts/ci/tests/test-fixture-e2e-build-reuse.sh`

Expected: FAIL because the current script always calls `build-for-testing` and does not pass a result-bundle path.

- [ ] **Step 3: Implement the optional reuse contract**

Require `XCTESTRUN_PATH` to exist when `SKIP_BUILD_FOR_TESTING=1`; otherwise preserve current behavior. Copy and patch the supplied `.xctestrun` rather than discovering another file. Append `-resultBundlePath "$XCTEST_RESULT_BUNDLE_PATH"` only when non-empty. Preserve every existing fixture-server and transcript/receipt assertion.

- [ ] **Step 4: Run contract and syntax tests**

```bash
bash scripts/ci/tests/test-fixture-e2e-build-reuse.sh
bash -n scripts/run-fixture-transcription-e2e-xcuitest.sh
```

Expected: PASS and no regression to the default build path.

- [ ] **Step 5: Commit**

```bash
git add scripts/run-fixture-transcription-e2e-xcuitest.sh scripts/ci/tests/test-fixture-e2e-build-reuse.sh
git commit -m "test: reuse UI shard build for fixture E2E"
```

---

### Task 5: Shard Receipt and Executor

**Files:**
- Create: `scripts/ci/shard-receipt.mjs`
- Create: `scripts/ci/run-ui-shard.sh`
- Create: `scripts/ci/tests/shard-receipt.test.mjs`
- Create: `scripts/ci/tests/test-run-ui-shard.sh`

**Interfaces:**
- Consumes: shard name, preflight receipt, build/test exit codes, expected selectors, ordinary and optional fixture `xcresulttool` summary JSON.
- Produces: `classifyShard(input: object): object` and `artifacts/receipt-${shard}.json` with `passed`, `test_failed`, or `infra_failed`.

- [ ] **Step 1: Write failing classification tests**

```javascript
import test from "node:test"
import assert from "node:assert/strict"
import { classifyShard } from "../shard-receipt.mjs"

test("classifies an assertion failure without retry", () => {
  const receipt = classifyShard({ preflightErrors: [], buildExit: 0, testExit: 65,
    testsStarted: 12, failedTests: ["testBeta"], skippedTests: [], missingTests: [],
    localAttempt: 1, secondsRemaining: 600 })
  assert.equal(receipt.classification, "test_failed")
  assert.equal(receipt.retryAllowed, false)
})

test("permits one pre-test infrastructure retry", () => {
  const receipt = classifyShard({ preflightErrors: [], buildExit: 65, testExit: null,
    testsStarted: 0, failedTests: [], skippedTests: [], missingTests: [],
    localAttempt: 1, secondsRemaining: 600 })
  assert.equal(receipt.classification, "infra_failed")
  assert.equal(receipt.retryAllowed, true)
})
```

- [ ] **Step 2: Verify the missing-module failure**

Run: `node --test scripts/ci/tests/shard-receipt.test.mjs`

Expected: FAIL because the receipt module does not exist.

- [ ] **Step 3: Implement receipt classification**

Test failures take precedence over infrastructure failures. Any unexpected skip, missing expected test, wrong SHA, or malformed summary is blocking. `retryAllowed` is true only when zero tests started, zero assertions failed, `localAttempt` is `1`, and at least 180 seconds remain before the shard deadline. `GITHUB_RUN_ATTEMPT` remains workflow metadata and must not be confused with the executor's local retry counter.

- [ ] **Step 4: Write the failing executor contract test**

Use fake `xcodebuild`, `xcrun`, preflight, cleanup, and fixture commands. Assert the executor calls `build-for-testing` once, runs only the selected ordinary tests, runs fixture E2E only for shard `c`, always invokes after-cleanup, and writes a receipt when a fake test command fails.

- [ ] **Step 5: Implement `run-ui-shard.sh`**

Require `FOIL_CI_SHARD`, `GITHUB_RUN_ID`, `GITHUB_RUN_ATTEMPT`, `GITHUB_SHA`, and `RUNNER_WORKSPACE`. Use run root `${RUNNER_WORKSPACE}/foil-ci-runs/${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT}-${FOIL_CI_SHARD}`. Set `RUN_LIVE_GROQ_TESTS=0` and `RUN_LIVE_MICROPHONE_TESTS=0`. Run:

```bash
xcodebuild build-for-testing \
  -scheme Foil -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -parallel-testing-enabled NO -maximum-concurrent-test-device-destinations 1 \
  -enableCodeCoverage NO -derivedDataPath "$derived_data" \
  -resultBundlePath "$build_result"

xcodebuild test-without-building \
  -xctestrun "$xctestrun_path" -destination 'platform=macOS,arch=arm64' \
  -enumerate-tests -test-enumeration-style flat -test-enumeration-format json \
  -test-enumeration-output-path "$enumeration_json"

node scripts/ci/ui-test-inventory.mjs check-built \
  --enumeration "$enumeration_json" --manifest scripts/ci/ui-test-shards.json

xcodebuild test-without-building \
  -xctestrun "$xctestrun_path" -destination 'platform=macOS,arch=arm64' \
  "${selectors[@]}" -resultBundlePath "$test_result"
```

For shard `c`, call the fixture script with the same `.xctestrun`, `SKIP_BUILD_FOR_TESTING=1`, and a separate fixture result bundle. Trap after-cleanup. Preserve all logs and receipts before deleting run-owned build state.

After the first attempt, generate a provisional receipt. When and only when it reports `infra_failed` with `retryAllowed: true`, run scoped cleanup and execute one second attempt in the same run root. Preserve both attempt logs and make the second receipt final. Never enter this branch for `test_failed`, unexpected skips, or missing expected tests.

- [ ] **Step 6: Run all focused tests**

```bash
node --test scripts/ci/tests/shard-receipt.test.mjs
bash scripts/ci/tests/test-run-ui-shard.sh
bash -n scripts/ci/run-ui-shard.sh
```

Expected: PASS for success, test failure, pre-test infrastructure failure, unexpected skip, fixture failure, and cleanup-on-signal fixtures.

- [ ] **Step 7: Commit**

```bash
git add scripts/ci/shard-receipt.mjs scripts/ci/run-ui-shard.sh scripts/ci/tests/shard-receipt.test.mjs scripts/ci/tests/test-run-ui-shard.sh
git commit -m "ci: run deterministic UI test shards"
```

---

### Task 6: Aggregate Gate Result

**Files:**
- Create: `scripts/ci/aggregate-ui-gate.mjs`
- Create: `scripts/ci/tests/aggregate-ui-gate.test.mjs`
- Create: `scripts/ci/tests/fixtures/receipts-pass/a.json`
- Create: `scripts/ci/tests/fixtures/receipts-pass/b.json`
- Create: `scripts/ci/tests/fixtures/receipts-pass/c.json`
- Create: `scripts/ci/tests/fixtures/receipts-wrong-sha/a.json`
- Create: `scripts/ci/tests/fixtures/receipts-wrong-sha/b.json`

**Interfaces:**
- Consumes: receipt directory, expected SHA, and expected shards `a,b,c`.
- Produces: `aggregateReceipts(receipts: object[], expectedSha: string): object`, `gate-summary.md`, `gate-summary.json`, and a nonzero exit for every blocking condition.

- [ ] **Step 1: Write failing aggregation tests**

```javascript
import test from "node:test"
import assert from "node:assert/strict"
import { aggregateReceipts } from "../aggregate-ui-gate.mjs"

const good = shard => ({ schemaVersion: 1, shard, sha: "abc", classification: "passed",
  expectedTests: [`test-${shard}`], executedTests: [`test-${shard}`], skippedTests: [] })

test("passes exactly three matching receipts", () => {
  assert.equal(aggregateReceipts([good("a"), good("b"), good("c")], "abc").status, "passed")
})

test("fails missing, duplicate, wrong-sha, and failed receipts", () => {
  const result = aggregateReceipts([good("a"), good("a"), { ...good("b"), sha: "wrong" }], "abc")
  assert.equal(result.status, "failed")
  assert.deepEqual(result.errors, ["duplicate receipt: a", "missing receipt: c", "wrong SHA in shard b: wrong"])
})
```

- [ ] **Step 2: Run tests and verify the missing-module failure**

Run: `node --test scripts/ci/tests/aggregate-ui-gate.test.mjs`

Expected: FAIL before implementation.

- [ ] **Step 3: Implement strict aggregation and Markdown output**

Require one receipt for each shard, matching SHA/baseline, no failed/skipped/missing tests, and complete timing/host fields. Group errors under `Product/test failures` and `Runner infrastructure failures`. Append the Markdown to `GITHUB_STEP_SUMMARY` when set, but never treat summary publication as evidence of success.

- [ ] **Step 4: Run success and failure fixtures**

```bash
node --test scripts/ci/tests/aggregate-ui-gate.test.mjs
node scripts/ci/aggregate-ui-gate.mjs --receipts scripts/ci/tests/fixtures/receipts-pass --sha abc --output-dir /tmp/foil-gate-pass
```

Expected: tests PASS; passing fixture exits zero; missing-receipt and wrong-SHA fixtures exit nonzero.

- [ ] **Step 5: Commit**

```bash
git add scripts/ci/aggregate-ui-gate.mjs scripts/ci/tests/aggregate-ui-gate.test.mjs scripts/ci/tests/fixtures/receipts-*
git commit -m "ci: aggregate deterministic UI gate receipts"
```

---

### Task 7: GitHub Actions Shadow Workflow and Make Targets

**Files:**
- Create: `.github/workflows/macos-deterministic-ui-gate.yml`
- Modify: `Makefile`
- Create: `scripts/ci/tests/test-workflow-contract.mjs`

**Interfaces:**
- Consumes: scripts and manifests from Tasks 1–6.
- Produces: dispatchable/non-required `Foil Deterministic UI Gate` workflow and local entry points `test-ci-scripts`, `ci-runner-preflight`, and `test-deterministic-ui-shard`.

- [ ] **Step 1: Write the failing workflow contract test**

Read the YAML as text and assert it contains `merge_group`, `workflow_dispatch`, shared concurrency with `cancel-in-progress: false`, matrix shards `[a, b, c]`, `fail-fast: false`, `max-parallel: 3`, runner label `foil-deterministic`, `if: always()` artifact uploads, and an aggregate job named exactly `Foil Deterministic UI Gate`. Also reject `pull_request_target`, live-provider secrets, `RUN_LIVE_GROQ_TESTS: "1"`, and `RUN_LIVE_MICROPHONE_TESTS: "1"`.

- [ ] **Step 2: Verify the contract fails because the workflow is absent**

Run: `node --test scripts/ci/tests/test-workflow-contract.mjs`

Expected: FAIL with missing workflow.

- [ ] **Step 3: Add Make targets**

```make
test-ci-scripts:
	node --test scripts/ci/tests/*.test.mjs
	bash scripts/ci/tests/test-runner-cleanup.sh
	bash scripts/ci/tests/test-fixture-e2e-build-reuse.sh
	bash scripts/ci/tests/test-run-ui-shard.sh

ci-runner-preflight:
	node scripts/ci/runner-preflight.mjs --baseline scripts/ci/runner-baseline.json --output "$${PREFLIGHT_OUTPUT:-preflight.json}"

test-deterministic-ui-shard:
	FOIL_CI_SHARD="$${FOIL_CI_SHARD:?set FOIL_CI_SHARD to a, b, or c}" scripts/ci/run-ui-shard.sh
```

- [ ] **Step 4: Create the shadow workflow**

Use `detect-changes` with `.github/scripts/app-ci-required.sh`; matrix jobs run only when `app_ci == 'true'`. Each matrix job has a fifteen-minute timeout, checks out the exact SHA, runs `scripts/ci/run-ui-shard.sh`, and uploads its artifact directory under `if: always()`. The aggregator is GitHub-hosted, runs under `if: always()`, downloads receipts, passes immediately with an explicit `not_applicable` summary for non-app changes, and otherwise invokes `aggregate-ui-gate.mjs`.

Add a parallel GitHub-hosted watchdog that uses the current run's Actions Jobs API with `GITHUB_TOKEN` and fails if all three shard jobs have not started within 180 seconds after dispatch. Because the workflow concurrency group serializes full gates, this detects an unavailable pool rather than normal pool contention. Give the workflow only `contents: read` and `actions: read` permissions.

- [ ] **Step 5: Validate locally**

```bash
make test-ci-scripts
git diff --check
node --test scripts/ci/tests/test-workflow-contract.mjs
```

Expected: PASS. If `actionlint` is installed, also run `actionlint .github/workflows/macos-deterministic-ui-gate.yml` and record its output.

- [ ] **Step 6: Commit**

```bash
git add .github/workflows/macos-deterministic-ui-gate.yml Makefile scripts/ci/tests/test-workflow-contract.mjs
git commit -m "ci: add shadow deterministic Mac UI gate"
```

---

### Task 8: Runner Bootstrap and Operations Runbook

**Files:**
- Create: `scripts/ci/bootstrap-foil-runner.sh`
- Create: `scripts/ci/tests/test-bootstrap-foil-runner.sh`
- Create: `docs/macos-deterministic-runner-pool.md`

**Interfaces:**
- Consumes: `RUNNER_REGISTRATION_TOKEN`, `--runner-dir`, `--runner-name`, and `--dry-run`.
- Produces: an installed Foil repository runner named `foil-mm1`, `foil-mm2`, or `foil-mm3` with the shared label; runbook commands for audit, rollback, reboot proof, and toolchain upgrade.

- [ ] **Step 1: Write failing bootstrap validation tests**

Use a temporary fake runner directory with stub `config.sh` and `svc.sh`. Assert the script rejects an unknown runner name, absent token outside dry-run, repository URL other than `https://github.com/usefoil/foil`, and a directory whose `.runner` points to another repository. Assert dry-run prints `--labels foil-deterministic` without printing the token.

- [ ] **Step 2: Verify the missing-script failure**

Run: `bash scripts/ci/tests/test-bootstrap-foil-runner.sh`

Expected: FAIL before implementation.

- [ ] **Step 3: Implement explicit idempotent bootstrap**

Accept only `foil-mm1`, `foil-mm2`, and `foil-mm3`. Refuse to delete or replace a runner associated with another repository. When the requested runner is already correctly configured, verify and exit zero. Otherwise require a registration token, run repository-scoped unattended configuration with `--replace`, install/start the per-user service, and never echo the token.

- [ ] **Step 4: Write the runbook with exact host operations**

Document:

- `mm1`, `mm2`, and `mm3` SSH aliases and expected runner names.
- Manual upgrade verification using `sw_vers`, `uname -m`, and `xcodebuild -version`.
- Reversible service disablement for unrelated runner directories using each directory's `svc.sh stop`; do not delete their `.runner` or credentials.
- Registration-token creation with `gh api -X POST repos/usefoil/foil/actions/runners/registration-token --jq .token`, passed through a non-logged environment variable.
- Bootstrap invocation, GitHub runner inventory query, dry-run preflight, reboot verification, bounded disk cleanup, and rollback.
- A warning that runner registration, service changes, OS upgrades, and branch-protection changes require an explicitly authorized maintenance window.

- [ ] **Step 5: Validate docs and tests**

```bash
bash scripts/ci/tests/test-bootstrap-foil-runner.sh
bash -n scripts/ci/bootstrap-foil-runner.sh
git diff --check
rg -n 'mm1|mm2|mm3|foil-deterministic|rollback|reboot' docs/macos-deterministic-runner-pool.md
```

Expected: PASS and every command/path referenced by the runbook exists or is an external system command identified as such.

- [ ] **Step 6: Commit**

```bash
git add scripts/ci/bootstrap-foil-runner.sh scripts/ci/tests/test-bootstrap-foil-runner.sh docs/macos-deterministic-runner-pool.md
git commit -m "docs: add deterministic Mac runner operations"
```

---

### Task 9: Provision the Three-Mini Pool in an Authorized Maintenance Window

**Files:**
- Modify only machine-local runner/toolchain state described in `docs/macos-deterministic-runner-pool.md`.
- Do not modify repository files in this task.

**Interfaces:**
- Consumes: committed bootstrap/runbook, GitHub registration tokens, administrator help for OS/Xcode installation where required.
- Produces: three online, healthy, repository-scoped runners with no competing active runner services.

- [ ] **Step 1: Capture the before-state receipt**

Run from the controller Mac:

```bash
for host in mm1 mm2 mm3; do
  ssh "$host" 'hostname; sw_vers; uname -m; xcodebuild -version; launchctl list | grep actions.runner || true'
done
gh api repos/usefoil/foil/actions/runners --jq '.runners[] | {name,status,busy,labels:[.labels[].name]}'
```

Expected: output matches the current-state table in the spec before mutation.

- [ ] **Step 2: Stop competing services without deleting their configuration**

On `mm2` stop `actions-runner` and `actions-runner-prcard-mac`; on `mm3` stop `actions-runner`. Use each directory's `svc.sh stop`, then prove only the intended Foil service will remain. Do not remove runner directories.

- [ ] **Step 3: Standardize macOS and Xcode**

Upgrade each host to macOS 26.5.2 build 25F84 and Xcode 26.6 build 17F113. Set the selected developer directory to `/Applications/Xcode.app/Contents/Developer`, complete first-launch components, and enable Developer Mode during the authorized administrator session.

Run:

```bash
for host in mm1 mm2 mm3; do
  ssh "$host" 'sw_vers; xcodebuild -version; xcodebuild -runFirstLaunch -checkForNewerComponents'
done
```

Expected: every host reports the pinned build pair and exits zero.

- [ ] **Step 4: Register or repair one Foil runner per host**

Push the reviewed implementation branch, then create the same standard checkout path on each host:

```bash
implementation_branch="$(git branch --show-current)"
git push -u origin "$implementation_branch"
for host in mm1 mm2 mm3; do
  ssh "$host" 'mkdir -p "$HOME/Developer"; if [ ! -d "$HOME/Developer/foil-ci/.git" ]; then git clone https://github.com/usefoil/foil.git "$HOME/Developer/foil-ci"; fi'
  ssh "$host" "git -C \"\$HOME/Developer/foil-ci\" fetch origin '$implementation_branch' && git -C \"\$HOME/Developer/foil-ci\" checkout -B '$implementation_branch' 'origin/$implementation_branch'"
done
```

Use unique registration tokens and names `foil-mm1`, `foil-mm2`, and `foil-mm3`. Invoke `scripts/ci/bootstrap-foil-runner.sh` from `$HOME/Developer/foil-ci` on each host. Never reuse or print tokens.

- [ ] **Step 5: Verify online inventory and host preflight**

```bash
gh api repos/usefoil/foil/actions/runners --jq '.runners[] | {name,status,busy,labels:[.labels[].name]}'
for host in mm1 mm2 mm3; do
  ssh "$host" 'cd "$HOME/Developer/foil-ci" && make ci-runner-preflight PREFLIGHT_OUTPUT=/tmp/foil-preflight.json && jq . /tmp/foil-preflight.json'
done
```

Expected: exactly three Foil runners are online and idle; each receipt is `healthy`; no unrelated runner service is active.

- [ ] **Step 6: Reboot-proof one host at a time**

Reboot only after explicit confirmation. After login recovery, verify the GUI test account, runner service, GitHub online state, and preflight receipt before moving to the next host.

- [ ] **Step 7: Record an infrastructure commit only if the runbook needed correction**

If commands differed from documented behavior, update the runbook with the proven commands, run `git diff --check`, and commit `docs: correct Mac runner bootstrap evidence`. Otherwise make no repository commit for machine-local state.

---

### Task 10: Shadow Runs, Failure Injection, and Enforcement Decision

**Files:**
- Create: `docs/evidence/macos-deterministic-gate/shadow-runs.md`
- Modify: `scripts/ci/ui-test-shards.json` only when measured timing requires rebalancing.
- Modify: repository branch-protection/merge-queue settings only after explicit approval.

**Interfaces:**
- Consumes: dispatchable workflow, three healthy runners, and artifacts from ten runs.
- Produces: acceptance evidence, balanced shards, and a human-approved decision to require `Foil Deterministic UI Gate`.

- [ ] **Step 1: Dispatch the first shadow run**

```bash
implementation_branch="$(git branch --show-current)"
gh workflow run macos-deterministic-ui-gate.yml --repo usefoil/foil --ref "$implementation_branch"
gh run watch --repo usefoil/foil --exit-status
```

Do not substitute `main` until the workflow exists there.

- [ ] **Step 2: Record the evidence receipt**

For each run record run URL, SHA, runner-to-shard mapping, build/test/total durations, classifications, unexpected skips, artifacts, and the strongest realistic failure mode tested. Do not record a green workflow as proof without inspecting all three receipts.

- [ ] **Step 3: Execute ten representative runs**

Include two consecutive runs of the same SHA and enough app-impacting changes to exercise normal merge-group behavior. Require zero unexplained flakes, zero silent skips, and complete artifacts.

- [ ] **Step 4: Rebalance by measured duration**

Move explicit test identifiers between `a`, `b`, and `c` so the slowest shard is close to the other two. Run the inventory audit and commit:

```bash
node scripts/ci/ui-test-inventory.mjs check --source FoilUITests/FoilUITests.swift --manifest scripts/ci/ui-test-shards.json
git add scripts/ci/ui-test-shards.json docs/evidence/macos-deterministic-gate/shadow-runs.md
git commit -m "ci: balance deterministic UI test shards"
```

- [ ] **Step 5: Try to disprove runner isolation**

Run the same SHA after rotating natural shard assignments, inject a stale Foil process, select the wrong Xcode on one host, and take one runner offline. Verify the gate cleans only scoped state, detects drift before build, produces `infra_failed`, and never reports false success. Restore the pinned state after every injection.

- [ ] **Step 6: Evaluate the service objectives**

Calculate median total duration and maximum healthy-run duration from receipts. Acceptance requires median below ten minutes and every healthy run below fifteen minutes. If the target is missed, first rebalance tests and remove redundant waits; do not reduce coverage.

- [ ] **Step 7: Run the full repository verification**

```bash
make test-ci-scripts
make test
make build-warnings-as-errors
node scripts/ci/ui-test-inventory.mjs check --source FoilUITests/FoilUITests.swift --manifest scripts/ci/ui-test-shards.json
git diff --check
```

Expected: every command PASS. Record any skipped live/hardware checks as out of scope, not as passes.

- [ ] **Step 8: Request explicit enforcement approval**

Present the ten-run evidence, failure-injection results, current required checks, and exact branch-protection change. Do not mutate repository rules until the user approves that external state change.

- [ ] **Step 9: Enable and verify the required check after approval**

Preserve every existing required check while adding `Foil Deterministic UI Gate`. Queue one app-impacting PR and verify GitHub will not merge it until the aggregate check succeeds. Record the run URL and merge-queue evidence in `shadow-runs.md`.

- [ ] **Step 10: Commit final evidence**

```bash
git add docs/evidence/macos-deterministic-gate/shadow-runs.md
git commit -m "docs: record deterministic Mac gate acceptance"
```

## Final Verification Receipt

Before claiming completion, report:

```text
Claim: Every deterministic Foil UI test gates the merge queue across three interchangeable Mac minis.
Strongest realistic failure mode: A missing test, machine drift, runner outage, or stale GUI state produces a false green result.
Evidence: Inventory audit; ten shadow-run receipts; wrong-Xcode, stale-process, offline-runner, reboot, and test-failure injections; required-check merge-queue run.
Residual risk / follow-up: Live providers, real microphone, third-party paste behavior, notarized installs, and Codex exploratory testing remain separate and explicitly out of scope.
```
