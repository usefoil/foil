import fs from "node:fs"
import path from "node:path"

export const EXPECTED_RUNNERS = Object.freeze(["foil-mm1", "foil-mm2", "foil-mm3"])
export const READINESS_CLASSIFICATIONS = Object.freeze([
  "passed", "skipped", "cancelled", "infrastructure_failed"
])
export const READINESS_EVIDENCE_FIELDS = Object.freeze([
  "runnerName", "hostname", "architecture", "productVersion", "buildVersion",
  "xcodeVersion", "xcodeBuild", "consoleUser", "screenLocked",
  "developerModeEnabled", "freeBytes", "runnerOs", "runnerArch", "activeRunnerServices"
])
const baseline = JSON.parse(fs.readFileSync(new URL("./runner-baseline.json", import.meta.url), "utf8"))

const isNonEmptyString = value => typeof value === "string" && value.length > 0
const isStringArray = value => Array.isArray(value) && value.every(isNonEmptyString)

export function sameExactSet(left, right) {
  return Array.isArray(left) && Array.isArray(right) &&
    new Set(left).size === left.length && new Set(right).size === right.length &&
    left.length === right.length && left.every(value => right.includes(value))
}

function validPreflight(value, runnerName) {
  const facts = value?.facts
  return value?.schemaVersion === 1 && value.status === "healthy" &&
    Array.isArray(value.errors) && value.errors.length === 0 && facts?.runnerName === runnerName &&
    sameExactSet(Object.keys(facts), READINESS_EVIDENCE_FIELDS) &&
    isNonEmptyString(facts.hostname) && facts.architecture === baseline.architecture &&
    facts.productVersion === baseline.productVersion && facts.buildVersion === baseline.buildVersion &&
    facts.xcodeVersion === baseline.xcodeVersion && facts.xcodeBuild === baseline.xcodeBuild &&
    baseline.allowedConsoleUsers.includes(facts.consoleUser) &&
    Number.isFinite(facts.freeBytes) && facts.freeBytes >= baseline.minimumFreeBytes &&
    facts.runnerOs === "macOS" && facts.runnerArch === "ARM64" &&
    facts.screenLocked === false && facts.developerModeEnabled === true &&
    Array.isArray(facts.activeRunnerServices) && facts.activeRunnerServices.length === 1 &&
    facts.activeRunnerServices[0] === `actions.runner.usefoil-foil.${runnerName}`
}

function validSchema(receipt) {
  return receipt && typeof receipt === "object" && receipt.schemaVersion === 1 &&
    receipt.kind === "foil_runner_readiness" && EXPECTED_RUNNERS.includes(receipt.runnerName) &&
    isNonEmptyString(receipt.sha) && isNonEmptyString(receipt.runId) &&
    isNonEmptyString(receipt.workflowAttempt) && isNonEmptyString(receipt.observedAt) &&
    Number.isFinite(Date.parse(receipt.observedAt)) &&
    READINESS_CLASSIFICATIONS.includes(receipt.classification) &&
    receipt.claimPolicy === "shadow_advisory" && receipt.cleanup?.bounded === true &&
    ["passed", "failed"].includes(receipt.cleanup?.status) &&
    isStringArray(receipt.evidenceFields) && sameExactSet(receipt.evidenceFields, READINESS_EVIDENCE_FIELDS)
}

export function aggregateReadinessReceipts(receipts, expected, now = Date.now(), maxAgeSeconds = 900) {
  const errors = []
  if (!Array.isArray(receipts) || !expected || typeof expected !== "object" ||
      !isNonEmptyString(expected.sha) || !isNonEmptyString(expected.runId) ||
      !isNonEmptyString(expected.workflowAttempt) || !Number.isFinite(now) ||
      !Number.isFinite(maxAgeSeconds) || maxAgeSeconds <= 0) {
    return { status: "failed", classification: "infrastructure_failed", errors: ["invalid aggregate input"] }
  }

  const byRunner = new Map()
  for (const receipt of receipts) {
    if (!validSchema(receipt)) {
      errors.push(`malformed receipt: ${String(receipt?.runnerName ?? "unknown")}`)
      continue
    }
    if (byRunner.has(receipt.runnerName)) errors.push(`duplicate receipt: ${receipt.runnerName}`)
    else byRunner.set(receipt.runnerName, receipt)
  }
  for (const runner of EXPECTED_RUNNERS) {
    if (!byRunner.has(runner)) errors.push(`missing receipt: ${runner}`)
  }

  for (const runner of EXPECTED_RUNNERS) {
    const receipt = byRunner.get(runner)
    if (!receipt) continue
    if (receipt.sha !== expected.sha) errors.push(`wrong SHA: ${runner}`)
    if (receipt.runId !== expected.runId || receipt.workflowAttempt !== expected.workflowAttempt) {
      errors.push(`wrong workflow identity: ${runner}`)
    }
    const ageMilliseconds = now - Date.parse(receipt.observedAt)
    if (ageMilliseconds < 0 || ageMilliseconds > maxAgeSeconds * 1000) errors.push(`stale receipt: ${runner}`)
    if (receipt.classification !== "passed") errors.push(`${receipt.classification} receipt: ${runner}`)
    if (!validPreflight(receipt.preflight, runner)) errors.push(`invalid preflight: ${runner}`)
    if (receipt.cleanup.status !== "passed") errors.push(`cleanup failed: ${runner}`)
  }

  const complete = EXPECTED_RUNNERS.map(name => byRunner.get(name)).filter(Boolean)
  if (complete.length === EXPECTED_RUNNERS.length) {
    const names = complete.map(receipt => receipt.runnerName)
    const hosts = complete.map(receipt => receipt.preflight?.facts?.hostname)
    const services = complete.map(receipt => receipt.preflight?.facts?.activeRunnerServices?.[0])
    if (!sameExactSet(names, EXPECTED_RUNNERS)) errors.push("receipts do not match the expected runner set")
    if (new Set(hosts).size !== EXPECTED_RUNNERS.length) errors.push("duplicate runner hostname identity")
    if (new Set(services).size !== EXPECTED_RUNNERS.length) errors.push("duplicate runner service identity")
  }
  return { status: errors.length === 0 ? "passed" : "failed",
    classification: errors.length === 0 ? "passed" : "infrastructure_failed", errors }
}

function parseArguments(argv) {
  const values = {}
  for (let index = 0; index < argv.length; index += 2) {
    const key = argv[index]
    const value = argv[index + 1]
    if (!["--receipts", "--sha", "--run-id", "--attempt", "--output"].includes(key) || !isNonEmptyString(value)) {
      throw new Error("usage: --receipts DIR --sha SHA --run-id ID --attempt N --output PATH")
    }
    values[key.slice(2)] = value
  }
  for (const key of ["receipts", "sha", "run-id", "attempt", "output"]) {
    if (!values[key]) throw new Error("usage: --receipts DIR --sha SHA --run-id ID --attempt N --output PATH")
  }
  return values
}

function main(argv) {
  const options = parseArguments(argv)
  let receipts
  try {
    receipts = fs.readdirSync(options.receipts).filter(name => name.endsWith(".json")).sort()
      .map(name => JSON.parse(fs.readFileSync(path.join(options.receipts, name), "utf8")))
  } catch {
    receipts = [{ runnerName: "unreadable" }]
  }
  const result = aggregateReadinessReceipts(receipts, {
    sha: options.sha, runId: options["run-id"], workflowAttempt: options.attempt
  })
  fs.mkdirSync(path.dirname(options.output), { recursive: true })
  fs.writeFileSync(options.output, `${JSON.stringify(result, null, 2)}\n`)
  console.log(JSON.stringify(result))
  return result.status === "passed" ? 0 : 1
}

if (import.meta.url === `file://${process.argv[1]}`) {
  try { process.exitCode = main(process.argv.slice(2)) }
  catch (error) { console.error(error.message); process.exitCode = 1 }
}
