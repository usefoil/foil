import assert from "node:assert/strict"
import fs from "node:fs"
import os from "node:os"
import path from "node:path"
import { spawnSync } from "node:child_process"
import test from "node:test"
import { verifyUnitTestResult } from "../verify-unit-test-result.mjs"

const passed = { result: "Passed", failedTests: 0, passedTests: 1021, skippedTests: 4 }

test("accepts executed passing tests, independent of JSON whitespace", () => {
  for (const indent of [undefined, 2]) {
    assert.doesNotThrow(() => verifyUnitTestResult(JSON.parse(JSON.stringify(passed, null, indent)), 0))
  }
})

test("rejects compact failures and inconsistent or incomplete summaries", () => {
  for (const summary of [
    JSON.parse('{"result":"Failed","failedTests":21,"passedTests":1000}'),
    { ...passed, failedTests: 21 },
    { ...passed, result: "Failed" },
    { ...passed, result: "Unknown" },
    { ...passed, failedTests: "0" },
    { ...passed, failedTests: undefined },
    { ...passed, passedTests: 0 },
    { ...passed, passedTests: 0.5 },
    {}, null,
  ]) assert.throws(() => verifyUnitTestResult(summary, 0))
})

test("a passing bundle cannot override xcodebuild failure or timeout", () => {
  for (const code of [65, 137, 143, undefined, NaN, "0"]) {
    assert.throws(() => verifyUnitTestResult(passed, code))
  }
})

test("CLI fails closed for missing, empty, malformed, failed, and nonzero-exit evidence", () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), "foil-unit-result-"))
  const file = path.join(directory, "summary.json")
  const script = new URL("../verify-unit-test-result.mjs", import.meta.url)
  const run = code => spawnSync(process.execPath, [script.pathname, String(code), file], { encoding: "utf8" })
  try {
    assert.equal(run(0).status, 1)
    for (const text of ["", "not JSON", JSON.stringify({ ...passed, failedTests: 21 })]) {
      fs.writeFileSync(file, text)
      assert.equal(run(0).status, 1)
    }
    fs.writeFileSync(file, JSON.stringify(passed))
    assert.equal(run(65).status, 1)
    assert.equal(run(0).status, 0)
  } finally {
    fs.rmSync(directory, { recursive: true, force: true })
  }
})

test("hosted unit workflow runs the validator and never replaces failures with exit zero", () => {
  const source = fs.readFileSync(new URL("../../../.github/workflows/ci.yml", import.meta.url), "utf8")
  const unitJob = source.split("  unit-tests:")[1].split("      - name: Test summary")[0]
  assert.match(unitJob, /node --test scripts\/ci\/tests\/unit-test-result\.test\.mjs/)
  assert.match(unitJob, /node scripts\/ci\/verify-unit-test-result\.mjs "\$TEST_EXIT" "\$SUMMARY_FILE"/)
  assert.doesNotMatch(unitJob, /All tests passed per results bundle|grep -q.*Failed|exit 0/)
})
