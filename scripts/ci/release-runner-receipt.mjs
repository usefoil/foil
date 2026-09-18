import fs from "node:fs"
import { EXPECTED_RUNNERS, READINESS_EVIDENCE_FIELDS } from "./release-runner-contract.mjs"

function parse(argv) {
  const values = {}
  for (let index = 0; index < argv.length; index += 2) {
    const key = argv[index], value = argv[index + 1]
    if (!["--preflight", "--cleanup-status", "--classification", "--output"].includes(key) || !value) {
      throw new Error("usage: --preflight PATH --cleanup-status passed|failed --classification CLASS --output PATH")
    }
    values[key.slice(2)] = value
  }
  return values
}

function requiredEnvironment(name) {
  const value = process.env[name]
  if (!value) throw new Error(`missing ${name}`)
  return value
}

function main(argv) {
  const options = parse(argv)
  const runnerName = requiredEnvironment("RUNNER_NAME")
  if (!EXPECTED_RUNNERS.includes(runnerName)) throw new Error("unexpected runner identity")
  const source = JSON.parse(fs.readFileSync(options.preflight, "utf8"))
  const facts = Object.fromEntries(READINESS_EVIDENCE_FIELDS.map(name => [name, source.facts?.[name]]))
  const receipt = {
    schemaVersion: 1,
    kind: "foil_runner_readiness",
    claimPolicy: "shadow_advisory",
    runnerName,
    sha: requiredEnvironment("GITHUB_SHA"),
    runId: requiredEnvironment("GITHUB_RUN_ID"),
    workflowAttempt: requiredEnvironment("GITHUB_RUN_ATTEMPT"),
    observedAt: new Date().toISOString(),
    classification: options.classification,
    evidenceFields: READINESS_EVIDENCE_FIELDS,
    preflight: { schemaVersion: source.schemaVersion, status: source.status, errors: source.errors, facts },
    cleanup: { bounded: true, status: options["cleanup-status"] }
  }
  fs.writeFileSync(options.output, `${JSON.stringify(receipt, null, 2)}\n`)
}

try { main(process.argv.slice(2)) }
catch (error) { console.error(error.message); process.exitCode = 1 }
