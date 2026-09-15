import test from "node:test"
import assert from "node:assert/strict"
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
    malformedSummary: false, interrupted: false, retryAllowed: false,
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
