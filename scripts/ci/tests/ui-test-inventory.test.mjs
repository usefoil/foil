import test from "node:test"
import assert from "node:assert/strict"
import { execFileSync } from "node:child_process"
import { discoverEnumeratedTests, discoverTests, validateManifest } from "../ui-test-inventory.mjs"

test("discovers XCTest methods in source order", () => {
  const source = "func testAlpha() {}\n  func testBeta() throws {}\n"
  assert.deepEqual(discoverTests(source), ["testAlpha", "testBeta"])
})

test("normalizes Xcode JSON enumeration identifiers", () => {
  const enumeration = { values: [{ identifier: "FoilUITests/FoilUITests/testAlpha()" }] }
  assert.deepEqual(discoverEnumeratedTests(enumeration), ["testAlpha"])
})

test("rejects missing, duplicate, stale, and overlapping assignments", () => {
  const manifest = {
    schemaVersion: 1,
    suite: "FoilUITests/FoilUITests",
    shards: { a: ["testAlpha"], b: ["testAlpha"], c: ["testStale"] },
    specialTests: { testFixture: { shard: "c", command: "make test-fixture-transcription-e2e" } },
    excluded: { testFixture: { reason: "overlap", workflow: "fixture.yml" } }
  }
  assert.deepEqual(validateManifest(["testAlpha", "testBeta", "testFixture"], manifest), [
    "duplicate assignment: testAlpha",
    "overlapping assignment and exclusion: testFixture",
    "stale assignment: testStale",
    "unassigned test: testBeta"
  ])
})

test("rejects missing and unknown shards", () => {
  const manifest = {
    schemaVersion: 1,
    suite: "FoilUITests/FoilUITests",
    shards: { a: [], b: [], unexpected: [] },
    specialTests: {},
    excluded: {}
  }
  assert.deepEqual(validateManifest([], manifest), [
    "missing shard: c",
    "unknown shard: unexpected"
  ])
})

test("rejects non-array shard assignments and invalid special-test shards", () => {
  const manifest = {
    schemaVersion: 1,
    suite: "FoilUITests/FoilUITests",
    shards: { a: [], b: "testBeta", c: [] },
    specialTests: { testAlpha: { shard: "unexpected", command: "make test-fixture-transcription-e2e" } },
    excluded: {}
  }
  assert.deepEqual(validateManifest(["testAlpha"], manifest), [
    "invalid shard assignments: b",
    "invalid special-test shard: testAlpha (unexpected)"
  ])
})

test("prints ordinary selectors from the default manifest", () => {
  const selectors = execFileSync("node", ["scripts/ci/ui-test-inventory.mjs", "selectors", "--shard", "a"], {
    encoding: "utf8"
  }).trim().split("\n")
  assert.ok(selectors.length > 0)
  assert.match(selectors[0], /^-only-testing:FoilUITests\/FoilUITests\/test/)
})
