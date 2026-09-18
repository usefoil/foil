import assert from "node:assert/strict"
import fs from "node:fs"
import test from "node:test"

const source = fs.readFileSync("FoilUITests/FoilUITests.swift", "utf8")

function body(name) {
  const start = source.indexOf(`func ${name}()`)
  assert.notEqual(start, -1, `missing ${name}`)
  const next = source.indexOf("\n    func test", start + 1)
  return source.slice(start, next === -1 ? source.length : next)
}

test("cleanup pane assertion uses the stable control observed in the failed accessibility tree", () => {
  const observedIdentifiers = new Set(["settings.root", "settings.cleanupGroups.modePicker"])
  assert.equal(observedIdentifiers.has("settings.cleanupGroups.root"), false)
  assert.equal(observedIdentifiers.has("settings.cleanupGroups.modePicker"), true)
  const testBody = body("testAppShellShowsAllSettingsSidebarPanes")
  assert.match(testBody, /navID: "appShell\.nav\.settings\.cleanup",\s*requiredID: "settings\.cleanupGroups\.modePicker"/)
  assert.doesNotMatch(testBody, /requiredID: "settings\.cleanupGroups\.root"/)
})

test("delivered signifier assertion waits through the observed processing label", () => {
  const observedLabels = ["Processing recording", "Processing recording", "Recording delivered"]
  assert.notEqual(observedLabels[0], "Recording delivered", "the old immediate assertion reproduces the failure")
  assert.equal(observedLabels.find(label => label === "Recording delivered"), "Recording delivered")
  const testBody = body("testLiveAudioSignifierHidesIdleByDefaultAndShowsActiveStates")
  assert.match(testBody, /waitForElementLabelOrValue\(signifier, containing: "Recording delivered", timeout: 4\)/)
  assert.match(testBody, /XCTAssertEqual\(signifier\.label, "Recording delivered"\)/)
})
