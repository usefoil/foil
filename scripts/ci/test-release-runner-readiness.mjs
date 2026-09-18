import assert from "node:assert/strict"
import fs from "node:fs"
import os from "node:os"
import path from "node:path"
import { spawnSync } from "node:child_process"
import test from "node:test"
import { aggregateReadinessReceipts, EXPECTED_RUNNERS } from "./release-runner-contract.mjs"

const NOW = Date.parse("2026-09-18T12:00:00Z")
const expected = { sha: "abc", runId: "42", workflowAttempt: "1" }
const evidenceFields = [
  "runnerName", "hostname", "architecture", "productVersion", "buildVersion", "xcodeVersion",
  "xcodeBuild", "consoleUser", "screenLocked", "developerModeEnabled", "freeBytes",
  "runnerOs", "runnerArch", "activeRunnerServices"
]

function good(runnerName) {
  return {
    schemaVersion: 1, kind: "foil_runner_readiness", claimPolicy: "shadow_advisory",
    runnerName, sha: "abc", runId: "42", workflowAttempt: "1",
    observedAt: "2026-09-18T11:59:00Z", classification: "passed", evidenceFields,
    preflight: { schemaVersion: 1, status: "healthy", errors: [], facts: {
      runnerName, hostname: `${runnerName}.local`, architecture: "arm64", productVersion: "27.0",
      buildVersion: "26A428", xcodeVersion: "27.0", xcodeBuild: "27A266a", consoleUser: "foilci",
      screenLocked: false, developerModeEnabled: true, freeBytes: 40000000000,
      runnerOs: "macOS", runnerArch: "ARM64",
      activeRunnerServices: [`actions.runner.usefoil-foil.${runnerName}`]
    } },
    cleanup: { bounded: true, status: "passed" }
  }
}
const all = () => EXPECTED_RUNNERS.map(good)

test("requires exactly foil-mm1, foil-mm2, and foil-mm3 with unique identities", () => {
  assert.deepEqual(EXPECTED_RUNNERS, ["foil-mm1", "foil-mm2", "foil-mm3"])
  assert.equal(aggregateReadinessReceipts(all(), expected, NOW).status, "passed")
  const duplicate = all(); duplicate[2].preflight.facts.hostname = duplicate[1].preflight.facts.hostname
  assert.match(aggregateReadinessReceipts(duplicate, expected, NOW).errors.join("\n"), /duplicate runner hostname/)
})

test("fails closed for missing and duplicate receipts", () => {
  const missing = aggregateReadinessReceipts(all().slice(0, 2), expected, NOW)
  const duplicate = aggregateReadinessReceipts([good("foil-mm1"), ...all()], expected, NOW)
  assert.match(missing.errors.join("\n"), /missing receipt: foil-mm3/)
  assert.match(duplicate.errors.join("\n"), /duplicate receipt: foil-mm1/)
  assert.equal(missing.status, "failed"); assert.equal(duplicate.status, "failed")
})

test("rejects stale, skipped, cancelled, infrastructure-failed, and malformed receipts", () => {
  for (const [label, mutate, pattern] of [
    ["stale", r => { r.observedAt = "2026-09-18T11:00:00Z" }, /stale receipt/],
    ["skipped", r => { r.classification = "skipped" }, /skipped receipt/],
    ["cancelled", r => { r.classification = "cancelled" }, /cancelled receipt/],
    ["infrastructure", r => { r.classification = "infrastructure_failed" }, /infrastructure_failed receipt/],
    ["malformed", r => { delete r.preflight }, /invalid preflight/],
  ]) test(label, () => {
    const receipts = all(); mutate(receipts[0])
    const result = aggregateReadinessReceipts(receipts, expected, NOW)
    assert.equal(result.status, "failed"); assert.match(result.errors.join("\n"), pattern)
  })
})

test("rejects truncated or ill-typed allowlisted preflight facts", () => {
  for (const [label, mutate] of [
    ["missing xcodeVersion", facts => { delete facts.xcodeVersion }],
    ["missing freeBytes", facts => { delete facts.freeBytes }],
    ["wrong architecture", facts => { facts.architecture = "x86_64" }],
    ["wrong product version", facts => { facts.productVersion = "26.0" }],
    ["wrong build version", facts => { facts.buildVersion = "unexpected" }],
    ["wrong Xcode build", facts => { facts.xcodeBuild = 27 }],
    ["wrong console user", facts => { facts.consoleUser = "daily-driver" }],
    ["non-finite free space", facts => { facts.freeBytes = "40000000000" }],
    ["insufficient free space", facts => { facts.freeBytes = 1 }],
    ["ill-typed lock state", facts => { facts.screenLocked = "false" }],
    ["extra non-allowlisted fact", facts => { facts.rawEnvironment = "must-not-pass" }],
  ]) test(label, () => {
    const receipts = all(); mutate(receipts[0].preflight.facts)
    const result = aggregateReadinessReceipts(receipts, expected, NOW)
    assert.equal(result.status, "failed")
    assert.match(result.errors.join("\n"), /invalid preflight: foil-mm1/)
  })
})

test("workflow remains dispatch-only, shadow-only, read-only, and exact-set aggregated", () => {
  const source = fs.readFileSync(new URL("../../.github/workflows/release-runner-readiness.yml", import.meta.url), "utf8")
  assert.match(source, /workflow_dispatch:/)
  assert.doesNotMatch(source, /pull_request:|push:|merge_group:|secrets\.|contents:\s*write/)
  assert.match(source, /Foil Release Runner Readiness \(Shadow Only\)/)
  assert.match(source, /release-runner-contract\.mjs/)
  assert.match(source, /matrix:\s*\n\s*slot: \[1, 2, 3\]/)
})

test("each matrix slot uploads a unique receipt basename before flat aggregation", () => {
  const workflow = fs.readFileSync(new URL("../../.github/workflows/release-runner-readiness.yml", import.meta.url), "utf8")
  const executor = fs.readFileSync(new URL("./run-release-runner-readiness.sh", import.meta.url), "utf8")
  assert.match(executor, /receipt="\$artifact_root\/receipt-\$READINESS_SLOT\.json"/)
  assert.match(workflow, /path: artifacts\/readiness-\$\{\{ matrix\.slot \}\}\/receipt-\$\{\{ matrix\.slot \}\}\.json/)
  assert.match(workflow, /merge-multiple: true/)
  const basenames = [1, 2, 3].map(slot => `receipt-${slot}.json`)
  assert.equal(new Set(basenames).size, 3)
  assert.deepEqual([...basenames].sort(), ["receipt-1.json", "receipt-2.json", "receipt-3.json"])

  const root = fs.mkdtempSync(path.join(os.tmpdir(), "foil-readiness-flat-download-"))
  try {
    const receipts = path.join(root, "receipts"), output = path.join(root, "summary", "result.json")
    fs.mkdirSync(receipts)
    all().forEach((receipt, index) => {
      receipt.observedAt = new Date().toISOString()
      fs.writeFileSync(path.join(receipts, basenames[index]), JSON.stringify(receipt))
    })
    const contract = new URL("./release-runner-contract.mjs", import.meta.url).pathname
    const result = spawnSync(process.execPath, [contract, "--receipts", receipts, "--sha", "abc",
      "--run-id", "42", "--attempt", "1", "--output", output], { encoding: "utf8" })
    assert.equal(result.status, 0, result.stderr)
    assert.deepEqual(JSON.parse(fs.readFileSync(output, "utf8")), {
      status: "passed", classification: "passed", errors: []
    })
  } finally { fs.rmSync(root, { recursive: true, force: true }) }
})

test("bounded cleanup refuses unknown content and removes only its owned empty run root", () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "foil-readiness-cleanup-"))
  try {
    const parent = path.join(root, "foil-readiness-runs"), run = path.join(parent, "42-1-1")
    fs.mkdirSync(run, { recursive: true }); fs.writeFileSync(path.join(run, ".foil-readiness-owned"), "42-1-1\n")
    const script = new URL("./release-readiness-cleanup.sh", import.meta.url).pathname
    const env = { ...process.env, GITHUB_RUN_ID: "42", GITHUB_RUN_ATTEMPT: "1", READINESS_SLOT: "1", RUNNER_TEMP: root }
    fs.writeFileSync(path.join(run, "unexpected"), "keep")
    const refused = spawnSync("bash", [script, "--run-root", run], { env, encoding: "utf8" })
    assert.notEqual(refused.status, 0); assert.ok(fs.existsSync(path.join(run, "unexpected")))
    fs.rmSync(path.join(run, "unexpected"))
    const cleaned = spawnSync("bash", [script, "--run-root", run], { env, encoding: "utf8" })
    assert.equal(cleaned.status, 0, cleaned.stderr); assert.equal(fs.existsSync(run), false)

    const outsideParent = path.join(root, "outside", "foil-readiness-runs")
    const outside = path.join(outsideParent, "42-1-1"), link = path.join(parent, "42-1-1")
    fs.mkdirSync(outside, { recursive: true }); fs.writeFileSync(path.join(outside, ".foil-readiness-owned"), "42-1-1\n")
    fs.symlinkSync(outside, link)
    const escaped = spawnSync("bash", [script, "--run-root", link], { env, encoding: "utf8" })
    assert.notEqual(escaped.status, 0); assert.ok(fs.existsSync(path.join(outside, ".foil-readiness-owned")))
  } finally { fs.rmSync(root, { recursive: true, force: true }) }
})

test("receipt sources contain no secret, signing, transcript, audio, document-path, or raw-env payload fields", () => {
  const forbidden = /api.?key|secret|password|token|signing|keychain|transcript|audio|documents?|environment|process\.env\s*[),}]/i
  for (const receipt of all()) assert.doesNotMatch(JSON.stringify(receipt), forbidden)
  const builder = fs.readFileSync(new URL("./release-runner-receipt.mjs", import.meta.url), "utf8")
  assert.doesNotMatch(builder, /\.\.\.process\.env|Object\.entries\(process\.env\)/)
})
