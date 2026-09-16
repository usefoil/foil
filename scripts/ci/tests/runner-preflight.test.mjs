import test from "node:test"
import assert from "node:assert/strict"
import fs from "node:fs"
import os from "node:os"
import path from "node:path"
import { compareFacts, runPreflight } from "../runner-preflight.mjs"

const baseline = {
  architecture: "arm64", productVersion: "27.0", buildVersion: "26A428",
  xcodeVersion: "27.0", xcodeBuild: "27A266a", minimumFreeBytes: 30_000_000_000,
  allowedRunnerNames: ["foil-mm1", "foil-mm2", "foil-mm3"],
  allowedConsoleUsers: ["foilci"]
}

test("accepts an exact healthy runner", () => {
  const facts = { ...baseline, runnerName: "foil-mm2", consoleUser: "foilci",
    freeBytes: 40_000_000_000, developerModeEnabled: true, runnerOs: "macOS",
    runnerArch: "ARM64", activeRunnerServices: ["actions.runner.usefoil-foil.foil-mm2"] }
  assert.deepEqual(compareFacts(baseline, facts), [])
})

test("checked-in baseline requires the dedicated foilci console user", () => {
  const checkedInBaseline = JSON.parse(fs.readFileSync(new URL("../runner-baseline.json", import.meta.url), "utf8"))
  const healthyFacts = JSON.parse(fs.readFileSync(new URL("./fixtures/healthy-runner.json", import.meta.url), "utf8"))
  assert.deepEqual(compareFacts(checkedInBaseline, { ...healthyFacts, consoleUser: "foilci" }), [])
  assert.deepEqual(compareFacts(checkedInBaseline, { ...healthyFacts, consoleUser: "neonwatty" }), [
    "consoleUser: expected one of foilci, got neonwatty"
  ])
})

test("checked-in baseline pins the accepted macOS 27 and Xcode 27 builds", () => {
  const checkedInBaseline = JSON.parse(fs.readFileSync(new URL("../runner-baseline.json", import.meta.url), "utf8"))
  assert.deepEqual({
    productVersion: checkedInBaseline.productVersion,
    buildVersion: checkedInBaseline.buildVersion,
    xcodeVersion: checkedInBaseline.xcodeVersion,
    xcodeBuild: checkedInBaseline.xcodeBuild
  }, {
    productVersion: "27.0",
    buildVersion: "26A428",
    xcodeVersion: "27.0",
    xcodeBuild: "27A266a"
  })
})

test("reports toolchain drift and competing services", () => {
  const facts = { architecture: "arm64", productVersion: "27.0", buildVersion: "26A428",
    xcodeVersion: "26.3", xcodeBuild: "17C529", runnerName: "foil-mm2",
    consoleUser: "foilci", freeBytes: 40_000_000_000, developerModeEnabled: true,
    runnerOs: "macOS", runnerArch: "ARM64",
    activeRunnerServices: ["actions.runner.usefoil-foil.foil-mm2", "actions.runner.mean-weasel.mac-mini-2"] }
  assert.deepEqual(compareFacts(baseline, facts), [
    "active runner service count: expected 1, got 2",
    "xcodeBuild: expected 27A266a, got 17C529",
    "xcodeVersion: expected 27.0, got 26.3"
  ])
})

test("rejects missing and non-finite free space", () => {
  const facts = { ...baseline, runnerName: "foil-mm2", consoleUser: "foilci",
    developerModeEnabled: true, runnerOs: "macOS", runnerArch: "ARM64",
    activeRunnerServices: ["actions.runner.usefoil-foil.foil-mm2"] }
  assert.deepEqual(compareFacts(baseline, facts), [
    "freeBytes: expected at least 30000000000, got missing"
  ])
  assert.deepEqual(compareFacts(baseline, { ...facts, freeBytes: Number.NaN }), [
    "freeBytes: expected at least 30000000000, got NaN"
  ])
})

test("rejects a sole runner service for another identity", () => {
  const facts = { ...baseline, runnerName: "foil-mm2", consoleUser: "foilci",
    freeBytes: 40_000_000_000, developerModeEnabled: true, runnerOs: "macOS",
    runnerArch: "ARM64", activeRunnerServices: ["actions.runner.mean-weasel.mac-mini-2"] }
  assert.deepEqual(compareFacts(baseline, facts), [
    "active runner service: expected actions.runner.usefoil-foil.foil-mm2, got actions.runner.mean-weasel.mac-mini-2"
  ])
})

test("writes a stable receipt when safe fact collection fails", () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), "foil-preflight-test-"))
  const output = path.join(directory, "receipt.json")
  try {
    assert.equal(runPreflight({ baseline: new URL("../runner-baseline.json", import.meta.url), output }, () => {
      throw new Error("collection failed")
    }), 1)
    assert.deepEqual(JSON.parse(fs.readFileSync(output, "utf8")), {
      schemaVersion: 1,
      status: "failed",
      facts: {},
      errors: ["preflight failed"]
    })
  } finally {
    fs.rmSync(directory, { recursive: true, force: true })
  }
})
