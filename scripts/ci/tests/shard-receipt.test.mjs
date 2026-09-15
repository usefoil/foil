import test from "node:test"
import assert from "node:assert/strict"
import fs from "node:fs"
import os from "node:os"
import path from "node:path"
import { spawnSync } from "node:child_process"
import { fileURLToPath } from "node:url"
import { classifyShard } from "../shard-receipt.mjs"

const base = { preflightErrors: [], buildExit: 0, testExit: 0,
  testsStarted: 1, failedTests: [], skippedTests: [], missingTests: [],
  localAttempt: 1, secondsRemaining: 600 }
const selector = "-only-testing:FoilUITests/FoilUITests/testAlpha"
const fixtureSelector = "-only-testing:FoilUITests/FoilUITests/testE2ETranscription"
function report(result = "Passed", name = "testAlpha") {
  return {
    summary: { title: "Tests", environmentDescription: "Mac", topInsights: [], result,
      totalTestCount: 1, passedTests: result === "Passed" ? 1 : 0,
      failedTests: result === "Failed" ? 1 : 0, skippedTests: result === "Skipped" ? 1 : 0,
      expectedFailures: 0, statistics: [], devicesAndConfigurations: [], testFailures: [] },
    tests: { devices: [], testPlanConfigurations: [], testNodes: [{ nodeType: "UI test bundle",
      name: "FoilUITests", children: [{ nodeType: "Test Case", name: `${name}()`,
        nodeIdentifier: `FoilUITests/${name}()`, result }] }] }
  }
}

test("classifies an assertion failure without retry, even alongside infrastructure errors", () => {
  const r = classifyShard({ ...base, preflightErrors: ["drift"], testExit: 65,
    testsStarted: 12, failedTests: ["testBeta"] })
  assert.equal(r.classification, "test_failed")
  assert.equal(r.retryAllowed, false)
})
test("permits one pre-test infrastructure retry independent of workflow attempt", () => {
  const r = classifyShard({ ...base, buildExit: 65, testExit: null, testsStarted: 0,
    workflowAttempt: "9" })
  assert.equal(r.classification, "infra_failed")
  assert.equal(r.retryAllowed, true)
})
for (const [name, changes] of Object.entries({
  "second local attempt": { localAttempt: 2 }, "179 seconds left": { secondsRemaining: 179 },
  "wrong SHA": { sha: "wrong", expectedSha: "wanted" },
  "malformed summary": { malformedSummary: true }, "unexpected skip": { skippedTests: ["testAlpha"] },
  "missing test": { missingTests: ["testAlpha"] }, "preflight drift": { preflightErrors: ["drift"] },
  "interruption": { interrupted: true }, "tests already started": { testsStarted: 1 }
})) test(`never retries ${name}`, () => {
  const r = classifyShard({ ...base, buildExit: 65, testExit: null, testsStarted: 0, ...changes })
  assert.notEqual(r.classification, "passed")
  assert.equal(r.retryAllowed, false)
})
test("retry threshold is inclusive at 180 seconds", () => {
  assert.equal(classifyShard({ ...base, buildExit: 65, testExit: null, testsStarted: 0,
    secondsRemaining: 180 }).retryAllowed, true)
})
test("proves successful expected test identity from the result tree", () => {
  const r = classifyShard({ ...base, expectedSelectors: [selector], ordinary: report() })
  assert.equal(r.classification, "passed")
  assert.equal(r.testsStarted, 1)
  assert.deepEqual(r.executedTests, ["FoilUITests/FoilUITests/testAlpha"])
  assert.deepEqual(r.expectedTests, ["FoilUITests/FoilUITests/testAlpha"])
})
for (const result of ["Failed", "Skipped"]) test(`blocks ${result} in summary and result tree`, () => {
  const r = classifyShard({ ...base, expectedSelectors: [selector], ordinary: report(result) })
  assert.equal(r.classification, "test_failed")
  assert.equal(r.retryAllowed, false)
})
test("same count but wrong identity cannot pass", () => {
  const r = classifyShard({ ...base, expectedSelectors: [selector.replace("Alpha", "Beta")], ordinary: report() })
  assert.equal(r.classification, "test_failed")
  assert.deepEqual(r.missingTests, ["FoilUITests/FoilUITests/testBeta"])
})
for (const mutation of [r => { r.summary = {} }, r => { r.tests = {} },
  r => { r.summary.totalTestCount = 2 }, r => { r.tests.testNodes[0].children[0].result = "unknown" },
  r => { r.tests.testNodes[0].children.push({ ...r.tests.testNodes[0].children[0] }) }
]) test("malformed or inconsistent result evidence is blocking without retry", () => {
  const ordinary = report(); mutation(ordinary)
  const r = classifyShard({ ...base, expectedSelectors: [selector], ordinary })
  assert.notEqual(r.classification, "passed")
  assert.equal(r.retryAllowed, false)
  assert.equal(r.malformedSummary, true)
})
test("fixture failure blocks a successful ordinary run", () => {
  const r = classifyShard({ ...base, expectedSelectors: [selector], ordinary: report(),
    fixtureExpectedSelectors: [fixtureSelector], fixture: report("Failed", "testE2ETranscription"), fixtureExit: 65 })
  assert.equal(r.classification, "test_failed")
  assert.equal(r.invalidSelectors, false)
  assert.equal(r.retryAllowed, false)
})
test("fixture command failure after passing tests still fails", () => {
  assert.equal(classifyShard({ ...base, expectedSelectors: [selector], ordinary: report(),
    fixtureExpectedSelectors: [fixtureSelector], fixture: report("Passed", "testE2ETranscription"), fixtureExit: 1 }).classification, "test_failed")
})
test("a signal without an assertion is infrastructure failure even after tests started", () => {
  assert.equal(classifyShard({ ...base, interrupted: true, testExit: 143 }).classification, "infra_failed")
})
test("successful exits without expected result evidence cannot pass", () => {
  const r = classifyShard({ ...base, expectedSelectors: [selector] })
  assert.equal(r.classification, "infra_failed")
  assert.equal(r.retryAllowed, false)
})
test("zero tests cannot pass", () => {
  assert.equal(classifyShard({ ...base, testsStarted: 0 }).classification, "infra_failed")
})
test("fixture success exit without a fixture result report cannot pass", () => {
  const r = classifyShard({ ...base, expectedSelectors: [selector], ordinary: report(),
    fixtureExpectedSelectors: [fixtureSelector], fixtureExit: 0 })
  assert.equal(r.classification, "infra_failed")
  assert.equal(r.invalidSelectors, false)
})
for (const [description, tree] of [["missing", undefined], ["malformed", {}]]) {
  test(`summary assertion evidence survives a ${description} test tree`, () => {
    const ordinary = report("Failed")
    ordinary.tests = tree
    const r = classifyShard({ ...base, expectedSelectors: [selector], ordinary,
      interrupted: true, testExit: 143 })
    assert.equal(r.classification, "test_failed")
    assert.equal(r.retryAllowed, false)
    assert.equal(r.testsStarted, 1)
    assert.equal(r.malformedSummary, true)
    assert.ok(r.failedTests.length > 0)
    assert.ok(r.diagnostics.some(message => message.includes("exact failed test names could not be recovered")))
  })
}
test("provisional shard-c expectations include the fixture and use deterministic canonical order", () => {
  const r = classifyShard({ ...base, shard: "c", buildExit: 65, testExit: null, testsStarted: 0,
    expectedSelectors: [selector.replace("Alpha", "Zulu"), `${selector}()`],
    fixtureExpectedSelectors: [selector.replace("Alpha", "E2ETranscription")],
    expectedTests: ["untrusted precomputed value"] })
  assert.deepEqual(r.expectedTests, ["FoilUITests/FoilUITests/testAlpha",
    "FoilUITests/FoilUITests/testE2ETranscription", "FoilUITests/FoilUITests/testZulu"])
  assert.equal(r.retryAllowed, true)
})
for (const selectors of [[`${selector}/*`], [selector, null], [selector, `${selector}()`],
  ["-only-testing:FoilUITests/FoilUITests"], selector, [], [` ${selector}`]]) {
  test("invalid or duplicate selectors cannot yield ambiguous expectations or a retry", () => {
    const r = classifyShard({ ...base, buildExit: 65, testExit: null, testsStarted: 0, expectedSelectors: selectors })
    assert.equal(r.classification, "infra_failed")
    assert.equal(r.retryAllowed, false)
    assert.deepEqual(r.expectedTests, [])
    assert.equal(r.invalidSelectors, true)
    assert.ok(r.diagnostics.some(message => message.includes("selector")))
  })
}
for (const contents of [`${selector}\n${selector}/*\n`, ` ${selector}\n`]) test("the CLI writes explicit failed expectations for an invalid selector file", () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), "foil-receipt-selectors-"))
  try {
    const preflight = path.join(directory, "preflight.json"), selectors = path.join(directory, "selectors.txt"), output = path.join(directory, "receipt.json")
    fs.writeFileSync(preflight, JSON.stringify({ schemaVersion: 1, status: "healthy", errors: [], facts: {} }))
    fs.writeFileSync(selectors, contents)
    const options = { shard: "a", "run-id": "123", "workflow-attempt": "9", sha: "abc", "expected-sha": "abc",
      "local-attempt": "1", "seconds-remaining": "600", "build-exit": "65", "test-exit": "null", "fixture-exit": "null",
      interrupted: "false", "infrastructure-kind": "build_failed", "cleanup-failed": "false", preflight, selectors,
      "artifact-dir": directory, output }
    const run = spawnSync(process.execPath, [fileURLToPath(new URL("../shard-receipt.mjs", import.meta.url)),
      ...Object.entries(options).flatMap(([key, value]) => [`--${key}`, value])], { encoding: "utf8" })
    assert.equal(run.status, 0, run.stderr)
    const receipt = JSON.parse(fs.readFileSync(output, "utf8"))
    assert.equal(receipt.schemaVersion, 1)
    assert.equal(receipt.classification, "infra_failed")
    assert.deepEqual(receipt.expectedTests, [])
    assert.equal(receipt.invalidSelectors, true)
    assert.equal(receipt.retryAllowed, false)
  } finally { fs.rmSync(directory, { recursive: true, force: true }) }
})
