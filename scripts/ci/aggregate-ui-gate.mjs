import fs from "node:fs"
import path from "node:path"

const expectedShards = ["a", "b", "c"]
const baseline = JSON.parse(fs.readFileSync(new URL("./runner-baseline.json", import.meta.url), "utf8"))

function isNonEmptyString(value) {
  return typeof value === "string" && value.length > 0
}

function isStringArray(value) {
  return Array.isArray(value) && value.every(isNonEmptyString)
}

function sameSet(left, right) {
  return new Set(left).size === left.length && new Set(right).size === right.length &&
    left.length === right.length && left.every(value => right.includes(value))
}

function validPreflight(receipt) {
  const preflight = receipt.preflight
  const facts = preflight?.facts
  if (!preflight || preflight.schemaVersion !== 1 || preflight.status !== "healthy" ||
      !Array.isArray(preflight.errors) || preflight.errors.length !== 0 || !facts) return false
  for (const name of ["architecture", "productVersion", "buildVersion", "xcodeVersion", "xcodeBuild"]) {
    if (facts[name] !== baseline[name]) return false
  }
  return isNonEmptyString(facts.hostname) && Number.isFinite(facts.freeBytes) && facts.freeBytes >= baseline.minimumFreeBytes &&
    baseline.allowedRunnerNames.includes(facts.runnerName) &&
    baseline.allowedConsoleUsers.includes(facts.consoleUser) && facts.developerModeEnabled === true &&
    facts.runnerOs === "macOS" && facts.runnerArch === "ARM64" &&
    Array.isArray(facts.activeRunnerServices) && facts.activeRunnerServices.length === 1 &&
    facts.activeRunnerServices[0] === `actions.runner.usefoil-foil.${facts.runnerName}`
}

function validMetadata(receipt) {
  return isNonEmptyString(receipt.runId) && isNonEmptyString(receipt.workflowAttempt) &&
    Number.isInteger(receipt.localAttempt) && receipt.localAttempt >= 1 &&
    Number.isFinite(receipt.secondsRemaining) && receipt.secondsRemaining >= 0
}

function validSchema(receipt) {
  return receipt && typeof receipt === "object" && receipt.schemaVersion === 1 &&
    expectedShards.includes(receipt.shard) && isNonEmptyString(receipt.sha) &&
    ["passed", "test_failed", "infra_failed"].includes(receipt.classification) &&
    isStringArray(receipt.expectedTests) && receipt.expectedTests.length > 0 && isStringArray(receipt.executedTests) &&
    ["failedTests", "skippedTests", "missingTests", "unexpectedTests"].every(name => isStringArray(receipt[name])) &&
    typeof receipt.malformedSummary === "boolean" && receipt.invalidSelectors === false && typeof receipt.interrupted === "boolean" &&
    typeof receipt.retryAllowed === "boolean" && [0, null].includes(receipt.buildExit) &&
    [0, null].includes(receipt.testExit) && [0, null].includes(receipt.fixtureExit)
}

export function aggregateReceipts(receipts, expectedSha) {
  const productTestFailures = []
  const runnerInfrastructureFailures = []
  if (!Array.isArray(receipts) || !isNonEmptyString(expectedSha)) {
    runnerInfrastructureFailures.push("invalid aggregate input")
    return summarize(productTestFailures, runnerInfrastructureFailures)
  }

  const byShard = new Map()
  for (const receipt of receipts) {
    const shard = receipt?.shard
    if (!expectedShards.includes(shard)) {
      runnerInfrastructureFailures.push(`invalid receipt shard: ${String(shard)}`)
      continue
    }
    if (byShard.has(shard)) runnerInfrastructureFailures.push(`duplicate receipt: ${shard}`)
    else byShard.set(shard, receipt)
  }
  for (const shard of expectedShards) if (!byShard.has(shard)) runnerInfrastructureFailures.push(`missing receipt: ${shard}`)

  for (const shard of expectedShards) {
    const receipt = byShard.get(shard)
    if (!receipt) continue
    if (!validSchema(receipt)) {
      runnerInfrastructureFailures.push(`malformed receipt: ${shard}`)
      continue
    }
    if (!validMetadata(receipt)) runnerInfrastructureFailures.push(`invalid timing/identity metadata in shard ${shard}`)
    if (receipt.sha !== expectedSha) runnerInfrastructureFailures.push(`wrong SHA in shard ${shard}: ${receipt.sha}`)
    if (!validPreflight(receipt)) runnerInfrastructureFailures.push(`invalid pinned baseline evidence in shard ${shard}`)
    if (receipt.classification !== "passed") {
      const destination = receipt.classification === "test_failed" ? productTestFailures : runnerInfrastructureFailures
      destination.push(`classification in shard ${shard}: ${String(receipt.classification)}`)
    }
    for (const [name, label] of [["failedTests", "failed tests"], ["skippedTests", "skipped tests"],
      ["missingTests", "missing tests"], ["unexpectedTests", "unexpected tests"]]) {
      if (receipt[name].length) productTestFailures.push(`${label} in shard ${shard}: ${receipt[name].join(", ")}`)
    }
    if (receipt.malformedSummary || receipt.interrupted || receipt.retryAllowed ||
        receipt.buildExit !== 0 || receipt.testExit !== 0 || (shard === "c" && receipt.fixtureExit !== 0) ||
        (shard !== "c" && receipt.fixtureExit !== null)) {
      runnerInfrastructureFailures.push(`incomplete runner execution evidence in shard ${shard}`)
    }
    if (!sameSet(receipt.expectedTests, receipt.executedTests)) {
      productTestFailures.push(`coverage mismatch in shard ${shard}`)
    }
  }
  const completeReceipts = expectedShards.map(shard => byShard.get(shard))
  if (completeReceipts.every(receipt => validSchema(receipt) && validMetadata(receipt))) {
    for (const key of ["runId", "workflowAttempt"]) {
      if (new Set(completeReceipts.map(receipt => receipt[key])).size !== 1) {
        runnerInfrastructureFailures.push(`mixed ${key} across receipts`)
      }
    }
  }
  return summarize(productTestFailures, runnerInfrastructureFailures)
}

function summarize(productTestFailures, runnerInfrastructureFailures) {
  const errors = [...runnerInfrastructureFailures, ...productTestFailures]
  return { status: errors.length === 0 ? "passed" : "failed", errors, productTestFailures, runnerInfrastructureFailures }
}

function markdown(result) {
  const lines = ["## Deterministic UI gate", "", `Status: **${result.status}**`, ""]
  for (const [heading, values] of [["Product/test failures", result.productTestFailures],
    ["Runner infrastructure failures", result.runnerInfrastructureFailures]]) {
    lines.push(`### ${heading}`, "")
    lines.push(...(values.length ? values.map(value => `- ${value}`) : ["- None"]), "")
  }
  return `${lines.join("\n")}\n`
}

function parseArguments(argv) {
  const options = {}
  for (let index = 0; index < argv.length; index += 2) {
    if (!["--receipts", "--sha", "--output-dir"].includes(argv[index]) || !isNonEmptyString(argv[index + 1])) throw new Error("usage: --receipts DIR --sha SHA --output-dir DIR")
    options[argv[index].slice(2)] = argv[index + 1]
  }
  if (!options.receipts || !options.sha || !options["output-dir"]) throw new Error("usage: --receipts DIR --sha SHA --output-dir DIR")
  return options
}

function main(argv) {
  const options = parseArguments(argv)
  let receipts
  try {
    receipts = fs.readdirSync(options.receipts).filter(name => name.endsWith(".json")).sort().map(name =>
      JSON.parse(fs.readFileSync(path.join(options.receipts, name), "utf8")))
  } catch {
    receipts = [{ shard: "unreadable" }]
  }
  const result = aggregateReceipts(receipts, options.sha)
  fs.mkdirSync(options["output-dir"], { recursive: true })
  fs.writeFileSync(path.join(options["output-dir"], "gate-summary.json"), `${JSON.stringify(result, null, 2)}\n`)
  const summary = markdown(result)
  fs.writeFileSync(path.join(options["output-dir"], "gate-summary.md"), summary)
  if (process.env.GITHUB_STEP_SUMMARY) fs.appendFileSync(process.env.GITHUB_STEP_SUMMARY, summary)
  return result.status === "passed" ? 0 : 1
}

if (import.meta.url === `file://${process.argv[1]}`) {
  try { process.exitCode = main(process.argv.slice(2)) }
  catch (error) { console.error(error.message); process.exitCode = 1 }
}
