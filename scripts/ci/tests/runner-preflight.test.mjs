import test from "node:test"
import assert from "node:assert/strict"
import { compareFacts } from "../runner-preflight.mjs"

const baseline = {
  architecture: "arm64", productVersion: "26.5.2", buildVersion: "25F84",
  xcodeVersion: "26.6", xcodeBuild: "17F113", minimumFreeBytes: 30_000_000_000,
  allowedRunnerNames: ["foil-mm1", "foil-mm2", "foil-mm3"],
  allowedConsoleUsers: ["neonwatty", "jeremywatt"]
}

test("accepts an exact healthy runner", () => {
  const facts = { ...baseline, runnerName: "foil-mm2", consoleUser: "jeremywatt",
    freeBytes: 40_000_000_000, developerModeEnabled: true, runnerOs: "macOS",
    runnerArch: "ARM64", activeRunnerServices: ["actions.runner.usefoil-foil.foil-mm2"] }
  assert.deepEqual(compareFacts(baseline, facts), [])
})

test("reports toolchain drift and competing services", () => {
  const facts = { architecture: "arm64", productVersion: "26.5.2", buildVersion: "25F84",
    xcodeVersion: "26.3", xcodeBuild: "17C529", runnerName: "foil-mm2",
    consoleUser: "jeremywatt", freeBytes: 40_000_000_000, developerModeEnabled: true,
    runnerOs: "macOS", runnerArch: "ARM64",
    activeRunnerServices: ["actions.runner.usefoil-foil.foil-mm2", "actions.runner.mean-weasel.mac-mini-2"] }
  assert.deepEqual(compareFacts(baseline, facts), [
    "active runner service count: expected 1, got 2",
    "xcodeBuild: expected 17F113, got 17C529",
    "xcodeVersion: expected 26.6, got 26.3"
  ])
})
