import fs from "node:fs"
import path from "node:path"

function canonicalSelector(value) {
  return value.replace(/^-only-testing:/, "").replace(/\(\)$/, "")
}

function expectedIdentifiers(selectors) {
  if (selectors === undefined) return []
  if (!Array.isArray(selectors)) throw new Error("expected selectors must be an array")
  if (selectors.length === 0) throw new Error("expected selectors must not be empty")
  return selectors.map(selector => {
    const match = typeof selector === "string" && selector.match(/^-only-testing:(FoilUITests\/FoilUITests\/test[A-Za-z0-9_]+)(?:\(\))?$/)
    if (!match) throw new Error("expected selector must identify one exact Foil XCTest method")
    return match[1]
  }).sort()
}

// Xcode's summary supplies counts; the test tree supplies identity. Require both.
function inspectReport(report, expected) {
  const output = { executedTests: [], failedTests: [], skippedTests: [], missingTests: [],
    unexpectedTests: [], testsStarted: 0, failedTestCount: 0, diagnostics: [], malformedSummary: false }
  try {
    const { summary, tests } = report
    const counts = ["totalTestCount", "passedTests", "failedTests", "skippedTests", "expectedFailures"]
    if (!counts.every(key => Number.isInteger(summary[key]) && summary[key] >= 0) ||
        !["Passed", "Failed", "Skipped", "Expected Failure"].includes(summary.result)) throw new Error("invalid summary")
    output.testsStarted = summary.passedTests + summary.failedTests + summary.expectedFailures
    // Retain assertion/skip evidence even if another part of the report is malformed.
    output.failedTestCount = summary.failedTests
    if (summary.failedTests) output.failedTests.push(`summary: ${summary.failedTests} failed tests`)
    if (summary.skippedTests || summary.expectedFailures) output.skippedTests.push("summary: skipped or expected failure")
    if (!Array.isArray(tests?.testNodes)) throw new Error("invalid test tree")
    const cases = []
    function visit(nodes, bundle = "") {
      for (const node of nodes) {
        if (!node || typeof node.nodeType !== "string") throw new Error("invalid test node")
        const target = /^(UI|Unit) test bundle$/.test(node.nodeType) ? node.name.replace(/\.xctest$/, "") : bundle
        if (node.nodeType === "Test Case") {
          let id = canonicalSelector(node.nodeIdentifier)
          if (id.split("/").length === 2 && target) id = `${target}/${id}`
          if (!/^[^/]+\/[^/]+\/test[A-Za-z0-9_]+$/.test(id) ||
              !["Passed", "Failed", "Skipped", "Expected Failure"].includes(node.result)) throw new Error("invalid test case")
          cases.push({ id, result: node.result })
        }
        if (node.children !== undefined) {
          if (!Array.isArray(node.children)) throw new Error("invalid children")
          visit(node.children, target)
        }
      }
    }
    visit(tests.testNodes)
    output.executedTests = cases.map(item => item.id)
    const results = { Passed: "passedTests", Failed: "failedTests", Skipped: "skippedTests", "Expected Failure": "expectedFailures" }
    if (summary.totalTestCount !== cases.length || new Set(output.executedTests).size !== cases.length ||
        Object.entries(results).some(([result, key]) => cases.filter(item => item.result === result).length !== summary[key])) {
      throw new Error("inconsistent counts")
    }
    output.failedTests = cases.filter(item => item.result === "Failed").map(item => item.id)
    output.skippedTests = cases.filter(item => ["Skipped", "Expected Failure"].includes(item.result)).map(item => item.id)
    if (summary.result !== "Passed" && !output.failedTests.length && !output.skippedTests.length) {
      throw new Error("inconsistent result")
    }
    if (expected !== null) {
      output.missingTests = expected.filter(id => !output.executedTests.includes(id))
      output.unexpectedTests = output.executedTests.filter(id => !expected.includes(id))
    }
  } catch {
    output.malformedSummary = true
    if (output.failedTestCount > 0) {
      output.diagnostics.push(`${output.failedTestCount} assertion failure(s) recorded in summary; exact failed test names could not be recovered`)
    }
  }
  return output
}

export function classifyShard(input) {
  const result = { ...input, schemaVersion: 1,
    testsStarted: input.testsStarted ?? 0, failedTests: [...(input.failedTests ?? [])],
    skippedTests: [...(input.skippedTests ?? [])], missingTests: [...(input.missingTests ?? [])],
    unexpectedTests: [], executedTests: [], failedTestCount: input.failedTests?.length ?? 0,
    diagnostics: [], expectedTests: [], invalidSelectors: false, malformedSummary: input.malformedSummary === true }
  let ordinaryExpected, fixtureExpected
  try {
    ordinaryExpected = expectedIdentifiers(input.expectedSelectors)
    fixtureExpected = expectedIdentifiers(input.fixtureExpectedSelectors)
    const expectedTests = [...ordinaryExpected, ...fixtureExpected].sort()
    if (new Set(expectedTests).size !== expectedTests.length) throw new Error("duplicate expected selectors identify the same XCTest method")
    result.expectedTests = expectedTests
  } catch (error) {
    result.invalidSelectors = true
    result.diagnostics.push(error.message)
    // Preserve known assertion evidence, but never publish a partial expected set.
    ordinaryExpected = null
    fixtureExpected = null
  }
  if (input.ordinary !== undefined || input.fixture !== undefined) {
    result.testsStarted = 0
    for (const [report, expected] of [[input.ordinary, ordinaryExpected], [input.fixture, fixtureExpected]]) {
      if (report === undefined) continue
      const inspected = inspectReport(report, expected)
      result.testsStarted += inspected.testsStarted
      result.failedTestCount += inspected.failedTestCount
      for (const key of ["executedTests", "failedTests", "skippedTests", "missingTests", "unexpectedTests", "diagnostics"]) result[key].push(...inspected[key])
      result.malformedSummary ||= inspected.malformedSummary
    }
  }
  delete result.ordinary
  delete result.fixture
  if (input.testExit === 0 && input.expectedSelectors?.length && input.ordinary === undefined) result.malformedSummary = true
  if (input.fixtureExit === 0 && input.fixtureExpectedSelectors?.length && input.fixture === undefined) result.malformedSummary = true
  const wrongSha = input.expectedSha !== undefined && input.sha !== input.expectedSha
  result.wrongSha = wrongSha
  const testFailure = result.failedTests.length > 0 || result.skippedTests.length > 0 ||
    result.missingTests.length > 0 || result.unexpectedTests.length > 0 ||
    (!input.interrupted && result.testsStarted > 0 && ((input.testExit != null && input.testExit !== 0) ||
      (input.fixtureExit != null && input.fixtureExit !== 0)))
  const infraFailure = result.expectedTests.length === 0 || result.invalidSelectors || result.testsStarted === 0 || wrongSha || result.malformedSummary || input.interrupted === true ||
    (input.preflightErrors?.length ?? 0) > 0 || (input.infrastructureErrors?.length ?? 0) > 0 ||
    input.buildExit !== 0 || input.testExit !== 0 ||
    (input.fixtureExpectedSelectors?.length > 0 && input.fixtureExit !== 0)
  result.classification = testFailure ? "test_failed" : infraFailure ? "infra_failed" : "passed"
  const preTestFailure = (Number.isInteger(input.buildExit) && input.buildExit !== 0 && input.testExit == null) ||
    input.infrastructureKind === "enumeration_command_failed"
  result.retryAllowed = result.classification === "infra_failed" && preTestFailure &&
    result.testsStarted === 0 && input.localAttempt === 1 && input.secondsRemaining >= 180 &&
    !wrongSha && !result.malformedSummary && !result.invalidSelectors && !input.interrupted &&
    !(input.preflightErrors?.length) && !(input.infrastructureErrors?.length)
  return result
}

function main(argv) {
  const options = {}
  for (let index = 0; index < argv.length; index += 2) {
    if (!argv[index].startsWith("--") || argv[index + 1] === undefined) throw new Error("expected --option value")
    options[argv[index].slice(2)] = argv[index + 1]
  }
  const read = file => JSON.parse(fs.readFileSync(file, "utf8"))
  const exitCode = key => options[key] === "null" ? null : Number(options[key])
  const directory = options["artifact-dir"]
  const input = {
    shard: options.shard, runId: options["run-id"], workflowAttempt: options["workflow-attempt"],
    sha: options.sha, expectedSha: options["expected-sha"],
    localAttempt: Number(options["local-attempt"]), secondsRemaining: Number(options["seconds-remaining"]),
    buildExit: exitCode("build-exit"), testExit: exitCode("test-exit"), fixtureExit: exitCode("fixture-exit"),
    interrupted: options.interrupted === "true", infrastructureKind: options["infrastructure-kind"],
    infrastructureErrors: [], preflightErrors: [],
    artifacts: { directory, preflight: options.preflight }
  }
  try {
    const preflight = read(options.preflight)
    if (preflight.schemaVersion !== 1 || !Array.isArray(preflight.errors) ||
        preflight.status !== "healthy" || preflight.errors.length) throw new Error("preflight unhealthy")
    input.preflight = preflight
  } catch { input.preflightErrors.push("preflight missing, malformed, or unhealthy") }
  try {
    input.expectedSelectors = fs.readFileSync(options.selectors, "utf8").split(/\r?\n/)
    if (input.expectedSelectors.at(-1) === "") input.expectedSelectors.pop()
  } catch {
    input.expectedSelectors = null
    input.infrastructureErrors.push("selectors missing or unreadable")
  }
  if (input.shard === "c") input.fixtureExpectedSelectors = ["-only-testing:FoilUITests/FoilUITests/testE2ETranscription"]
  for (const kind of ["ordinary", "fixture"]) {
    input.artifacts[`${kind}Result`] = path.join(directory, `${kind}.xcresult`)
    if (input[kind === "ordinary" ? "testExit" : "fixtureExit"] === null) continue
    input[kind] = {}
    for (const component of ["summary", "tests"]) {
      try { input[kind][component] = read(path.join(directory, `${kind}-${component}.json`)) }
      catch { input.malformedSummary = true }
    }
  }
  if (options["cleanup-failed"] === "true") input.infrastructureErrors.push("scoped cleanup failed")
  if (input.infrastructureKind && !["build_failed", "enumeration_command_failed"].includes(input.infrastructureKind)) {
    input.infrastructureErrors.push(input.infrastructureKind)
  }
  const receipt = classifyShard(input)
  fs.writeFileSync(options.output, `${JSON.stringify(receipt, null, 2)}\n`)
}

if (import.meta.url === `file://${process.argv[1]}`) {
  try { main(process.argv.slice(2)) } catch (error) { console.error(error.message); process.exitCode = 1 }
}
