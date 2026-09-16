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
const step = (job, id) => {
  const found = job.steps.find(value => value.id === id)
  assert.ok(found, `missing step ${id}`)
  return found
}
const always = value => assert.match(value, /^(?:\$\{\{\s*)?always\(\)(?:\s*\}\})?$/)

test("shadow triggers serialize the dedicated pool with only read permissions", () => {
  const config = workflow()
  assert.deepEqual(Object.keys(config.on).sort(), ["merge_group", "workflow_dispatch"])
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
  assert.equal(step(shards, "run").run, "bash scripts/ci/run-ui-shard.sh")
  assert.equal(step(shards, "run").env.FOIL_CI_SHARD, "${{ matrix.shard }}")
  const uploads = shards.steps.filter(s => s.uses?.startsWith("actions/upload-artifact@"))
  assert.equal(uploads.length, 2)
  for (const upload of uploads) always(upload.if)
  assert.ok(uploads.some(s => s.with.path === "artifacts/receipt-${{ matrix.shard }}.json" && s.with.name === "deterministic-receipt-${{ matrix.shard }}"))
  assert.ok(uploads.some(s => s.with.path === "artifacts/shard-${{ matrix.shard }}"))
  assert.equal(watchdog["runs-on"], "ubuntu-latest")
})

test("manual mm3 pilot runs one selected shard on only the named runner", () => {
  const config = workflow()
  const inputs = config.on.workflow_dispatch.inputs
  assert.deepEqual(inputs.mode.options, ["pool", "mm3-pilot"])
  assert.equal(inputs.mode.default, "pool")
  assert.deepEqual(inputs.pilot_shard.options, ["a", "b", "c"])
  assert.equal(inputs.pilot_shard.default, "a")

  const detect = config.jobs["detect-changes"]
  assert.match(detect.if, /inputs\.mode == 'pool'/)
  const pilot = config.jobs["mm3-pilot"]
  assert.equal(pilot.if, "github.event_name == 'workflow_dispatch' && inputs.mode == 'mm3-pilot'")
  assert.deepEqual(pilot["runs-on"], ["self-hosted", "macOS", "ARM64", "foil-deterministic", "foil-mm3"])
  assert.equal(pilot["timeout-minutes"], 15)
  assert.equal(step(pilot, "run").env.FOIL_CI_SHARD, "${{ inputs.pilot_shard }}")
  assert.equal(step(pilot, "run").run, "bash scripts/ci/run-ui-shard.sh")
  always(step(pilot, "validate").if)
  assert.match(step(pilot, "validate").run, /classification.*passed/s)
  assert.match(step(pilot, "validate").run, /runnerName.*foil-mm3/s)
  const uploads = pilot.steps.filter(value => value.uses?.startsWith("actions/upload-artifact@"))
  assert.equal(uploads.length, 2)
  for (const upload of uploads) always(upload.if)
  assert.match(config.jobs.aggregate.if, /inputs\.mode == 'pool'/)
})

test("mm3 pilot validator requires a passed receipt from foil-mm3", () => {
  const script = step(workflow().jobs["mm3-pilot"], "validate").run
  for (const [classification, runnerName, expected] of [
    ["passed", "foil-mm3", 0],
    ["infra_failed", "foil-mm3", 1],
    ["passed", "foil-mm2", 1],
  ]) {
    const directory = fs.mkdtempSync("/tmp/foil-mm3-pilot-contract-")
    try {
      fs.mkdirSync(`${directory}/artifacts`)
      fs.writeFileSync(`${directory}/artifacts/receipt-a.json`, JSON.stringify({
        shard: "a", classification,
        preflight: { status: "healthy", errors: [], facts: { runnerName } },
      }))
      const result = spawnSync("bash", ["-e", "-o", "pipefail", "-c", script], {
        cwd: directory, encoding: "utf8", env: { ...process.env, PILOT_SHARD: "a" },
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
      for (const name of ["aggregate-ui-gate.mjs", "runner-baseline.json"]) {
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
