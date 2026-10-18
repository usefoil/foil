import fs from "node:fs"
import { pathToFileURL } from "node:url"

export function verifyUnitTestResult(summary, xcodeExit) {
  if (!Number.isInteger(xcodeExit) || xcodeExit !== 0) {
    throw new Error(`xcodebuild did not succeed (exit ${xcodeExit})`)
  }
  if (!summary || summary.result !== "Passed" || summary.failedTests !== 0 ||
      !Number.isInteger(summary.passedTests) || summary.passedTests < 1) {
    throw new Error("The results bundle must report Passed, zero failures, and executed passing tests")
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    const [exitValue, summaryPath] = process.argv.slice(2)
    if (!exitValue || !/^\d+$/.test(exitValue) || !summaryPath) {
      throw new Error("Usage: verify-unit-test-result.mjs XCODE_EXIT SUMMARY_JSON")
    }
    const summary = JSON.parse(fs.readFileSync(summaryPath, "utf8"))
    verifyUnitTestResult(summary, Number(exitValue))
    console.log(`Verified ${summary.passedTests} passing tests with no failures and xcodebuild exit 0`)
  } catch (error) {
    console.error(`Unit test verification failed: ${error.message}`)
    process.exitCode = 1
  }
}
