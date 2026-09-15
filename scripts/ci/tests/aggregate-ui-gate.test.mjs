import test from "node:test"
import assert from "node:assert/strict"
import fs from "node:fs"
import os from "node:os"
import path from "node:path"
import { spawnSync } from "node:child_process"
import { fileURLToPath } from "node:url"
import { aggregateReceipts } from "../aggregate-ui-gate.mjs"

const facts = {
  hostname: "foil-mm1.local", architecture: "arm64", productVersion: "26.5.2", buildVersion: "25F84",
  xcodeVersion: "26.6", xcodeBuild: "17F113", minimumFreeBytes: undefined,
  freeBytes: 30000000000, runnerName: "foil-mm1", consoleUser: "neonwatty",
  developerModeEnabled: true, runnerOs: "macOS", runnerArch: "ARM64",
  activeRunnerServices: ["actions.runner.usefoil-foil.foil-mm1"]
}

function good(shard) {
  return {
    schemaVersion: 1, shard, sha: "abc", runId: "42", workflowAttempt: "3",
    localAttempt: 1, secondsRemaining: 600, classification: "passed",
    expectedTests: [`FoilUITests/FoilUITests/test${shard.toUpperCase()}`],
    executedTests: [`FoilUITests/FoilUITests/test${shard.toUpperCase()}`],
    failedTests: [], skippedTests: [], missingTests: [], unexpectedTests: [],
    malformedSummary: false, invalidSelectors: false, interrupted: false, retryAllowed: false,
    buildExit: 0, testExit: 0, fixtureExit: shard === "c" ? 0 : null,
    preflight: { schemaVersion: 1, status: "healthy", errors: [], facts: { ...facts,
      activeRunnerServices: [...facts.activeRunnerServices] } }
  }
}

test("passes exactly three complete matching receipts", () => {
  const result = aggregateReceipts([good("a"), good("b"), good("c")], "abc")
  assert.equal(result.status, "passed")
  assert.deepEqual(result.errors, [])
  assert.deepEqual(result.productTestFailures, [])
  assert.deepEqual(result.runnerInfrastructureFailures, [])
})

test("fails duplicate, missing, and wrong-SHA receipts", () => {
  const result = aggregateReceipts([good("a"), good("a"), { ...good("b"), sha: "wrong" }], "abc")
  assert.equal(result.status, "failed")
  assert.deepEqual(result.errors, ["duplicate receipt: a", "missing receipt: c", "wrong SHA in shard b: wrong"])
})

test("rejects malformed or incomplete evidence as runner infrastructure failures", () => {
  const incomplete = good("b")
  delete incomplete.preflight.facts.xcodeBuild
  const malformed = { ...good("a"), secondsRemaining: -1 }
  const result = aggregateReceipts([malformed, incomplete, good("c")], "abc")
  assert.equal(result.status, "failed")
  assert.deepEqual(result.productTestFailures, [])
  assert.match(result.runnerInfrastructureFailures.join("\n"), /invalid timing\/identity metadata in shard a/)
  assert.match(result.runnerInfrastructureFailures.join("\n"), /invalid pinned baseline evidence in shard b/)
})

test("rejects an empty expected-test list even when executed coverage is also empty", () => {
  const emptyCoverage = { ...good("a"), expectedTests: [], executedTests: [] }
  const result = aggregateReceipts([emptyCoverage, good("b"), good("c")], "abc")
  assert.equal(result.status, "failed")
  assert.match(result.runnerInfrastructureFailures.join("\n"), /malformed receipt: a/)
})

for (const invalidSelectors of [true, undefined, [], {}]) test("rejects every non-false invalid-selector state", () => {
  const receipt = good("a")
  if (invalidSelectors === undefined) delete receipt.invalidSelectors
  else receipt.invalidSelectors = invalidSelectors
  const result = aggregateReceipts([receipt, good("b"), good("c")], "abc")
  assert.equal(result.status, "failed")
  assert.match(result.runnerInfrastructureFailures.join("\n"), /malformed receipt: a/)
})

test("requires all receipts to share one run and workflow attempt", () => {
  const mixedRun = aggregateReceipts([good("a"), { ...good("b"), runId: "other" }, good("c")], "abc")
  const mixedAttempt = aggregateReceipts([good("a"), { ...good("b"), workflowAttempt: "other" }, good("c")], "abc")
  assert.equal(mixedRun.status, "failed")
  assert.match(mixedRun.runnerInfrastructureFailures.join("\n"), /mixed runId/)
  assert.equal(mixedAttempt.status, "failed")
  assert.match(mixedAttempt.runnerInfrastructureFailures.join("\n"), /mixed workflowAttempt/)
})

test("groups skips, missing tests, and failed classifications as product/test failures", () => {
  const skipped = { ...good("a"), skippedTests: ["FoilUITests/FoilUITests/testA"] }
  const missing = { ...good("b"), missingTests: ["FoilUITests/FoilUITests/testB"] }
  const failed = { ...good("c"), classification: "test_failed", failedTests: ["FoilUITests/FoilUITests/testC"] }
  const result = aggregateReceipts([skipped, missing, failed], "abc")
  assert.equal(result.status, "failed")
  assert.deepEqual(result.runnerInfrastructureFailures, [])
  assert.match(result.productTestFailures.join("\n"), /skipped tests in shard a/)
  assert.match(result.productTestFailures.join("\n"), /missing tests in shard b/)
  assert.match(result.productTestFailures.join("\n"), /classification in shard c: test_failed/)
})

test("requires exact expected and executed coverage", () => {
  const coverage = { ...good("b"), executedTests: ["FoilUITests/FoilUITests/testOther"] }
  const result = aggregateReceipts([good("a"), coverage, good("c")], "abc")
  assert.equal(result.status, "failed")
  assert.deepEqual(result.runnerInfrastructureFailures, [])
  assert.match(result.productTestFailures.join("\n"), /coverage mismatch in shard b/)
})

test("CLI writes both summaries and preserves failed status after summary append", () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), "foil-aggregate-cli-"))
  try {
    const passOutput = path.join(directory, "pass"), failOutput = path.join(directory, "fail")
    const stepSummary = path.join(directory, "step-summary.md")
    const script = fileURLToPath(new URL("../aggregate-ui-gate.mjs", import.meta.url))
    const pass = spawnSync(process.execPath, [script, "--receipts", fileURLToPath(new URL("./fixtures/receipts-pass", import.meta.url)),
      "--sha", "abc", "--output-dir", passOutput], { encoding: "utf8" })
    const failed = spawnSync(process.execPath, [script, "--receipts", fileURLToPath(new URL("./fixtures/receipts-wrong-sha", import.meta.url)),
      "--sha", "abc", "--output-dir", failOutput], { encoding: "utf8", env: { ...process.env, GITHUB_STEP_SUMMARY: stepSummary } })
    assert.equal(pass.status, 0, pass.stderr)
    assert.equal(JSON.parse(fs.readFileSync(path.join(passOutput, "gate-summary.json"), "utf8")).status, "passed")
    assert.match(fs.readFileSync(path.join(passOutput, "gate-summary.md"), "utf8"), /Status: \*\*passed\*\*/)
    assert.equal(failed.status, 1, failed.stderr)
    assert.equal(JSON.parse(fs.readFileSync(path.join(failOutput, "gate-summary.json"), "utf8")).status, "failed")
    assert.match(fs.readFileSync(stepSummary, "utf8"), /Status: \*\*failed\*\*/)
  } finally { fs.rmSync(directory, { recursive: true, force: true }) }
})
