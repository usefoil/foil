import assert from "node:assert/strict"
import fs from "node:fs"
import { createRequire } from "node:module"
import { spawnSync } from "node:child_process"
import test from "node:test"

// js-yaml is already installed by the repository's locked commitlint dependencies.
const { load } = createRequire(import.meta.url)("js-yaml")
const root = new URL("../../../", import.meta.url).pathname
const source = () => fs.readFileSync(new URL("../../../.github/workflows/macos-deterministic-ui-gate.yml", import.meta.url), "utf8")
const workflow = () => load(source())
const ciSource = () => fs.readFileSync(new URL("../../../.github/workflows/ci.yml", import.meta.url), "utf8")
const ciWorkflow = () => load(ciSource())
const step = (job, id) => {
  const found = job.steps.find(value => value.id === id)
  assert.ok(found, `missing step ${id}`)
  return found
}
const always = value => assert.match(value, /^(?:\$\{\{\s*)?always\(\)(?:\s*\}\})?$/)

test("persistent self-hosted Mac workflows require manual dispatch", () => {
  const workflows = new URL("../../../.github/workflows/", import.meta.url)
  for (const name of fs.readdirSync(workflows).filter(value => value.endsWith(".yml"))) {
    const config = load(fs.readFileSync(new URL(name, workflows), "utf8"))
    const selfHosted = Object.values(config.jobs ?? {}).some(job =>
      JSON.stringify(job["runs-on"] ?? "").includes("self-hosted"))
    if (!selfHosted) continue
    const triggers = Object.keys(config.on)
    assert.deepEqual(triggers, ["workflow_dispatch"], `${name} must not automatically run code on a persistent Mac`)
  }
})

test("shadow Mac pool is manually dispatched with only read permissions", () => {
  const config = workflow()
  assert.deepEqual(Object.keys(config.on), ["workflow_dispatch"])
  assert.deepEqual(config.permissions, { contents: "read", actions: "read" })
  assert.equal(config.concurrency["cancel-in-progress"], false)
  assert.equal(config.concurrency.group, "foil-deterministic-ui-gate")
  assert.doesNotMatch(source(), /secrets\.|pull_request_target|RUN_LIVE_(?:GROQ|MICROPHONE)_TESTS:\s*["']?1/)
  for (const job of Object.values(config.jobs)) {
    assert.equal(job.permissions, undefined)
    for (const value of job.steps) if (value.uses?.startsWith("actions/checkout@")) {
      assert.equal(value.with.ref, "${{ github.sha }}")
      assert.equal(value.with["persist-credentials"], false)
    }
  }
})

test("detector feeds gated three-way Mac matrix and parallel hosted watchdog", () => {
  const { "detect-changes": detect, shards, "start-watchdog": watchdog } = workflow().jobs
  assert.equal(detect["runs-on"], "ubuntu-latest")
  assert.equal(detect.steps.find(s => s.uses?.startsWith("actions/checkout@")).with["fetch-depth"], 0)
  assert.equal(detect.outputs.app_ci, "${{ steps.detect.outputs.app_ci }}")
  assert.match(step(detect, "detect").run, /bash \.github\/scripts\/app-ci-required\.sh/)
  assert.match(step(detect, "dispatch").run, /GITHUB_OUTPUT/)
  assert.equal(detect.outputs.dispatched_at, "${{ steps.dispatch.outputs.dispatched_at }}")
  for (const job of [shards, watchdog]) {
    assert.deepEqual(job.needs, ["detect-changes"])
    assert.equal(job.if, "needs.detect-changes.outputs.app_ci == 'true'")
  }
  assert.deepEqual(shards["runs-on"], ["self-hosted", "macOS", "ARM64", "foil-deterministic"])
  assert.equal(shards["timeout-minutes"], 15)
  assert.deepEqual(shards.strategy, { "fail-fast": false, "max-parallel": 3, matrix: { shard: ["a", "b", "c"] } })
  assert.equal(shards.name, "Deterministic UI shard ${{ matrix.shard }}")
  const capacity = step(shards, "capacity")
  assert.equal(capacity.name, "Wait for full deterministic runner pool")
  assert.equal(capacity.uses, "actions/github-script@v8")
  assert.equal(capacity.with["github-token"], "${{ github.token }}")
  assert.equal(capacity.env.DISPATCHED_AT, "${{ needs.detect-changes.outputs.dispatched_at }}")
  assert.equal(step(shards, "run").run, "bash scripts/ci/run-ui-shard.sh")
  assert.equal(step(shards, "run").env.FOIL_CI_SHARD, "${{ matrix.shard }}")
  assert.equal(step(shards, "run").env.FOIL_CI_SHARD_TIMEOUT_SECONDS, "660")
  const uploads = shards.steps.filter(s => s.uses?.startsWith("actions/upload-artifact@"))
  assert.equal(uploads.length, 2)
  for (const upload of uploads) assert.equal(upload.if, "always() && steps.capacity.outcome == 'success'")
  assert.ok(uploads.some(s => s.with.path === "artifacts/receipt-${{ matrix.shard }}.json" && s.with.name === "deterministic-receipt-${{ matrix.shard }}"))
  assert.ok(uploads.some(s => s.with.path === "artifacts/shard-${{ matrix.shard }}"))
  assert.equal(watchdog["runs-on"], "ubuntu-latest")
  assert.equal(capacity.with.script, step(watchdog, "watch").with.script)
})

test("manual pilot routes one selected shard to one approved runner", () => {
  const config = workflow()
  const inputs = config.on.workflow_dispatch.inputs
  assert.deepEqual(inputs.mode.options, ["pool", "runner-pilot"])
  assert.equal(inputs.mode.default, "pool")
  assert.deepEqual(inputs.pilot_runner.options, ["foil-mm1", "foil-mm2", "foil-mm3"])
  assert.equal(inputs.pilot_runner.default, "foil-mm3")
  assert.deepEqual(inputs.pilot_shard.options, ["a", "b", "c"])
  assert.equal(inputs.pilot_shard.default, "a")

  const detect = config.jobs["detect-changes"]
  assert.match(detect.if, /inputs\.mode == 'pool'/)
  const selection = config.jobs["pilot-selection"]
  assert.equal(selection["runs-on"], "ubuntu-latest")
  assert.equal(selection.if, "github.event_name == 'workflow_dispatch' && inputs.mode == 'runner-pilot'")
  assert.equal(selection.steps[0].env.PILOT_RUNNER, "${{ inputs.pilot_runner }}")
  const pilot = config.jobs["runner-pilot"]
  assert.deepEqual(pilot.needs, ["pilot-selection"])
  assert.equal(pilot.if, "github.event_name == 'workflow_dispatch' && inputs.mode == 'runner-pilot' && needs.pilot-selection.result == 'success'")
  assert.deepEqual(pilot["runs-on"], ["self-hosted", "macOS", "ARM64", "foil-deterministic", "${{ inputs.pilot_runner }}"])
  assert.equal(pilot["timeout-minutes"], 15)
  assert.equal(step(pilot, "run").env.FOIL_CI_SHARD, "${{ inputs.pilot_shard }}")
  assert.equal(step(pilot, "run").run, "bash scripts/ci/run-ui-shard.sh")
  always(step(pilot, "validate").if)
  assert.match(step(pilot, "validate").run, /classification.*passed/s)
  assert.equal(step(pilot, "validate").env.PILOT_RUNNER, "${{ inputs.pilot_runner }}")
  assert.match(step(pilot, "validate").run, /runnerName.*PILOT_RUNNER/s)
  const uploads = pilot.steps.filter(value => value.uses?.startsWith("actions/upload-artifact@"))
  assert.equal(uploads.length, 2)
  for (const upload of uploads) always(upload.if)
  assert.match(config.jobs.aggregate.if, /inputs\.mode == 'pool'/)
})

test("pilot selection accepts the named fleet and rejects unknown runners", () => {
  const selection = workflow().jobs["pilot-selection"].steps[0]
  assert.equal(selection.uses, undefined)
  assert.equal(selection.env.PILOT_RUNNER, "${{ inputs.pilot_runner }}")
  assert.doesNotMatch(selection.run, /github|gh |curl|secrets/)
  for (const [runner, expected] of [["foil-mm1", 0], ["foil-mm2", 0], ["foil-mm3", 0], ["foil-mm4", 1], ["", 1]]) {
    const result = spawnSync("bash", ["-e", "-o", "pipefail", "-c", selection.run], {
      encoding: "utf8", env: { ...process.env, PILOT_RUNNER: runner },
    })
    assert.equal(result.status, expected, result.stderr)
  }
})

test("pilot validator requires a passed receipt from the selected runner and shard", () => {
  const script = step(workflow().jobs["runner-pilot"], "validate").run
  for (const [selectedRunner, runnerName, shard, classification, mutation, expected] of [
    ["foil-mm1", "foil-mm1", "a", "passed", {}, 0],
    ["foil-mm1", "foil-mm1", "b", "passed", {}, 0],
    ["foil-mm3", "foil-mm3", "c", "passed", {}, 0],
    ["foil-mm1", "foil-mm2", "a", "passed", {}, 1],
    ["foil-mm3", "foil-mm3", "a", "infra_failed", {}, 1],
    ["foil-mm1", "foil-mm1", "b", "test_failed", {}, 1],
    ["foil-mm1", "foil-mm1", "b", "passed", { sha: "wrong" }, 1],
    ["foil-mm1", "foil-mm1", "b", "passed", { workflowAttempt: "old" }, 1],
    ["foil-mm1", "foil-mm1", "b", "passed", { executedTests: [] }, 1],
  ]) {
    const directory = fs.mkdtempSync("/tmp/foil-runner-pilot-contract-")
    try {
      fs.mkdirSync(`${directory}/artifacts`)
      fs.writeFileSync(`${directory}/artifacts/receipt-${shard}.json`, JSON.stringify({
        shard, classification, sha: "abc", runId: "42", workflowAttempt: "1",
        interrupted: false, buildExit: 0, testExit: 0, fixtureExit: shard === "c" ? 0 : null,
        expectedTests: ["FoilUITests/FoilUITests/testOne"], executedTests: ["FoilUITests/FoilUITests/testOne"],
        preflight: { status: "healthy", errors: [], facts: { runnerName } },
        ...mutation,
      }))
      const result = spawnSync("bash", ["-e", "-o", "pipefail", "-c", script], {
        cwd: directory, encoding: "utf8", env: { ...process.env, PILOT_SHARD: shard, PILOT_RUNNER: selectedRunner,
          GITHUB_SHA: "abc", GITHUB_RUN_ID: "42", GITHUB_RUN_ATTEMPT: "1" },
      })
      assert.equal(result.status, expected, result.stderr)
    } finally { fs.rmSync(directory, { recursive: true, force: true }) }
  }
})

test("aggregate waits for all evidence, downloads only flat receipts, and always publishes its summary", () => {
  const aggregate = workflow().jobs.aggregate
  assert.equal(aggregate.name, "Foil Deterministic UI Gate")
  assert.equal(aggregate["runs-on"], "ubuntu-latest")
  assert.match(aggregate.if, /always\(\)/)
  assert.match(aggregate.if, /inputs\.mode == 'pool'/)
  assert.deepEqual([...aggregate.needs].sort(), ["detect-changes", "shards", "start-watchdog"])
  const download = aggregate.steps.find(s => s.uses?.startsWith("actions/download-artifact@"))
  assert.equal(download.if, "needs.detect-changes.outputs.app_ci == 'true'")
  assert.deepEqual(download.with, { pattern: "deterministic-receipt-*", path: "receipts", "merge-multiple": true })
  always(step(aggregate, "aggregate").if)
  assert.deepEqual(step(aggregate, "aggregate").env, {
    APP_CI: "${{ needs.detect-changes.outputs.app_ci }}", DETECT_RESULT: "${{ needs.detect-changes.result }}",
    SHARDS_RESULT: "${{ needs.shards.result }}", WATCHDOG_RESULT: "${{ needs.start-watchdog.result }}",
  })
  const upload = aggregate.steps.find(s => s.uses?.startsWith("actions/upload-artifact@"))
  always(upload.if)
  assert.equal(upload.with.path, "gate-summary/")
})

async function runWatchdog(jobsAt, { now = 0, dispatched = "2026-09-15T00:00:00.000Z" } = {}) {
  const watchdog = workflow().jobs["start-watchdog"]
  const script = step(watchdog, "watch").with.script
  assert.equal(step(watchdog, "watch").with["github-token"], "${{ github.token }}")
  assert.equal(step(watchdog, "watch").env.DISPATCHED_AT, "${{ needs.detect-changes.outputs.dispatched_at }}")
  const epoch = Date.parse("2026-09-15T00:00:00.000Z")
  const failures = [], calls = []
  class Clock extends Date { static now() { return epoch + now } }
  const list = Symbol("current run jobs")
  const github = {
    rest: { actions: { listJobsForWorkflowRunAttempt: list } },
    paginate: async (endpoint, params) => {
      assert.equal(endpoint, list)
      assert.deepEqual(params, { owner: "owner", repo: "repo", run_id: 123, attempt_number: 2, per_page: 100 })
      calls.push(now)
      return jobsAt(now)
    },
  }
  const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor
  await new AsyncFunction("github", "context", "core", "process", "Date", "setTimeout", script)(
    github, { repo: { owner: "owner", repo: "repo" }, runId: 123 },
    { setFailed: message => failures.push(message), info() {} },
    { env: { DISPATCHED_AT: dispatched, GITHUB_RUN_ATTEMPT: "2" } }, Clock,
    (callback, delay) => { assert.ok(delay > 0 && delay <= 10000); now += delay; callback() },
  )
  return { failures, calls, elapsed: now }
}

const started = (shard, overrides = {}) => ({
  name: `Deterministic UI shard ${shard}`, status: "in_progress",
  runner_id: { a: 41, b: 42, c: 43 }[shard], started_at: "2026-09-15T00:00:30.000Z", ...overrides,
})

test("watchdog accepts all current-attempt shards including already completed jobs", async () => {
  const result = await runWatchdog(() => [started("a"), started("b"), started("c", { status: "completed" })], { now: 40000 })
  assert.deepEqual(result.failures, [])
  assert.equal(result.calls.length, 1)
})

test("watchdog rejects three shards started on fewer than three distinct runners", async () => {
  const result = await runWatchdog(() => [started("a"), started("b"), started("c", { runner_id: 42 })])
  assert.equal(result.failures.length, 1)
  assert.match(result.failures[0], /three distinct runner IDs/)
  assert.equal(result.elapsed, 180000)
})

test("watchdog waits for all shards and rejects missing, queued, stale, or late starts at 180 seconds", async () => {
  for (const last of [null, started("c", { status: "queued", runner_id: null }),
    started("c", { started_at: "2026-09-14T23:59:59.000Z" }), started("c", { started_at: "2026-09-15T00:03:00.001Z" }),
    started("c", { started_at: null }), started("c", { name: "Unrelated shard c" })]) {
    const result = await runWatchdog(() => [started("a"), started("b"), ...(last ? [last] : [])])
    assert.equal(result.failures.length, 1)
    assert.match(result.failures[0], /180|deadline/)
    assert.match(result.failures[0], /shard c/)
    assert.equal(result.elapsed, 180000)
  }
  const recovery = await runWatchdog(now => [started("a"), started("b"), ...(now >= 60000 ? [started("c")] : [])])
  assert.deepEqual(recovery.failures, [])
  assert.equal(recovery.elapsed, 60000)
})

test("watchdog does not restart the dispatch deadline when hosted scheduling is late", async () => {
  const result = await runWatchdog(() => [], { now: 190000 })
  assert.equal(result.failures.length, 1)
  assert.equal(result.calls.length, 1)
  const invalid = await runWatchdog(() => [], { dispatched: "" })
  assert.equal(invalid.failures.length, 1)
})

test("aggregate cannot turn failed prerequisites or an unknown detector into not_applicable", () => {
  const script = step(workflow().jobs.aggregate, "aggregate").run
  for (const [app, detect, shards, watchdog, expected, output] of [
    ["false", "success", "skipped", "skipped", 0, "not_applicable"],
    ["", "failure", "skipped", "skipped", 1, "detect"],
    ["true", "success", "success", "failure", 1, "180"],
  ]) {
    const directory = fs.mkdtempSync("/tmp/foil-workflow-contract-")
    try {
      const result = spawnSync("bash", ["-e", "-o", "pipefail", "-c", script], {
        cwd: directory, encoding: "utf8", env: { ...process.env,
          APP_CI: app, DETECT_RESULT: detect, SHARDS_RESULT: shards, WATCHDOG_RESULT: watchdog,
          GITHUB_SHA: "abc", GITHUB_STEP_SUMMARY: `${directory}/summary.md`,
        },
      })
      assert.equal(result.status, expected, result.stderr)
      assert.match(fs.readFileSync(`${directory}/summary.md`, "utf8"), new RegExp(output))
    } finally { fs.rmSync(directory, { recursive: true, force: true }) }
  }
})

test("Make exposes all script suites including the workflow contract", () => {
  const result = spawnSync("make", ["-n", "test-ci-scripts", "ci-runner-preflight", "test-deterministic-ui-shard"], { cwd: root, encoding: "utf8" })
  assert.equal(result.status, 0, result.stderr)
  for (const value of ["tests/*.test.mjs", "test-workflow-contract.mjs", "test-runner-cleanup.sh", "test-fixture-e2e-build-reuse.sh", "test-run-ui-shard.sh", "runner-preflight.mjs", "run-ui-shard.sh"]) assert.ok(result.stdout.includes(value), value)
})

test("CI makes the Agent Access contract and installed smoke required gates with retained evidence", () => {
  const config = ciWorkflow()
  const contract = config.jobs["agent-access-contract"]
  assert.equal(contract.name, "Agent Access Contract")
  assert.equal(contract["runs-on"], "macos-15")
  assert.equal(contract["timeout-minutes"], 15)
  const contractRun = contract.steps.find(value => value.run?.includes("make test-agent-access"))
  assert.ok(contractRun)
  assert.equal(contractRun.env.AGENT_ACCESS_RESULT_BUNDLE, "AgentAccessResults.xcresult")
  assert.match(contractRun.run, /make test-agent-access\n\s*make test-local-correction-performance/)
  const contractUpload = contract.steps.find(value => value.uses?.startsWith("actions/upload-artifact@"))
  always(contractUpload.if)
  assert.deepEqual(contractUpload.with, {
    name: "agent-access-results", path: "AgentAccessResults.xcresult",
    "retention-days": 14, "if-no-files-found": "error",
  })

  const installed = config.jobs["agent-access-installed"]
  assert.deepEqual(installed.needs, ["detect-changes"])
  assert.match(installed.if, /needs\.detect-changes\.outputs\.code == 'true'/)
  const installedRun = installed.steps.find(value => value.run === "make test-agent-access-installed")
  assert.deepEqual(installedRun.env, {
    AGENT_ACCESS_AD_HOC_SIGNING: "1",
    AGENT_ACCESS_SMOKE_ARTIFACT_DIR: "agent-access-installed-artifacts",
  })
  const installedUpload = installed.steps.find(value => value.uses?.startsWith("actions/upload-artifact@"))
  always(installedUpload.if)
  assert.deepEqual(installedUpload.with, {
    name: "agent-access-installed-artifacts", path: "agent-access-installed-artifacts",
    "retention-days": 14, "if-no-files-found": "error",
  })

  const gate = config.jobs["ci-gate"]
  assert.ok(gate.needs.includes("agent-access-contract"))
  assert.ok(gate.needs.includes("agent-access-installed"))
  const gateStep = gate.steps.find(value => value.run?.includes("Agent Access contract did not pass"))
  assert.equal(gateStep.env.AGENT_ACCESS_CONTRACT_RESULT, "${{ needs.agent-access-contract.result }}")
  assert.equal(gateStep.env.AGENT_ACCESS_INSTALLED_RESULT, "${{ needs.agent-access-installed.result }}")
  assert.match(gateStep.run, /AGENT_ACCESS_CONTRACT_RESULT.*!= "success"/)
  assert.match(gateStep.run, /for result in .*AGENT_ACCESS_INSTALLED_RESULT/)
})

test("CI includes all four Agent Access settings and proposal UI boundaries", () => {
  const matrix = ciWorkflow().jobs["ui-tests"].strategy.matrix.include
  const selected = matrix.flatMap(value => value.tests.match(/FoilUITests\/FoilUITests\/\w+/g) ?? [])
  for (const testName of [
    "testAgentAccessDefaultsOffCopiesCommandAndPersistsUntilDisabled",
    "testAgentAccessStartupErrorFailsClosedInSettings",
    "testAgentVocabularyProposalRemainsReviewableAfterAccessIsDisabled",
    "testAgentVocabularyProposalReviewedApplyCreatesCatalogEntriesWithoutEnablingSwitch",
  ]) assert.equal(selected.filter(value => value.endsWith(testName)).length, 1, testName)
})

test("aggregate runs the real receipt validator and cannot publish a passed summary after shard failure", () => {
  const script = step(workflow().jobs.aggregate, "aggregate").run
  for (const [fixture, sha, shards, expected] of [
    ["receipts-pass", "abc", "success", 0],
    ["receipts-pass", "wrong", "success", 1],
    ["receipts-pass", "abc", "failure", 1],
    ["receipts-wrong-sha", "abc", "success", 1],
  ]) {
    const directory = fs.mkdtempSync("/tmp/foil-workflow-contract-")
    try {
      fs.mkdirSync(`${directory}/scripts/ci`, { recursive: true })
      for (const name of ["aggregate-ui-gate.mjs", "release-runner-contract.mjs", "runner-baseline.json"]) {
        fs.copyFileSync(`${root}scripts/ci/${name}`, `${directory}/scripts/ci/${name}`)
      }
      fs.symlinkSync(`${root}scripts/ci/tests/fixtures/${fixture}`, `${directory}/receipts`)
      const result = spawnSync("bash", ["-e", "-o", "pipefail", "-c", script], {
        cwd: directory, encoding: "utf8", env: { ...process.env,
          APP_CI: "true", DETECT_RESULT: "success", SHARDS_RESULT: shards, WATCHDOG_RESULT: "success",
          GITHUB_SHA: sha, GITHUB_STEP_SUMMARY: `${directory}/summary.md`,
        },
      })
      assert.equal(result.status, expected, result.stderr)
      const markdown = fs.readFileSync(`${directory}/gate-summary/gate-summary.md`, "utf8")
      assert.match(markdown, expected === 0 ? /Status: \*\*passed\*\*/ : /Status: (?:\*\*)?failed/)
      if (fs.existsSync(`${directory}/gate-summary/gate-summary.json`)) {
        assert.equal(JSON.parse(fs.readFileSync(`${directory}/gate-summary/gate-summary.json`, "utf8")).status, expected === 0 ? "passed" : "failed")
      }
    } finally { fs.rmSync(directory, { recursive: true, force: true }) }
  }
})
