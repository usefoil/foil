import "./tests/test-workflow-contract.mjs"

import assert from "node:assert/strict"
import fs from "node:fs"
import test from "node:test"

test("deterministic UI aggregation reuses the exact release runner contract", () => {
  const source = fs.readFileSync(new URL("./aggregate-ui-gate.mjs", import.meta.url), "utf8")
  assert.match(source, /import \{ EXPECTED_RUNNERS, sameExactSet \} from "\.\/release-runner-contract\.mjs"/)
  assert.match(source, /sameExactSet\(baseline\.allowedRunnerNames, EXPECTED_RUNNERS\)/)
})
