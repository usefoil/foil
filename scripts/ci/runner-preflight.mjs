import fs from "node:fs"
import os from "node:os"
import { execFileSync } from "node:child_process"

function actual(value) {
  return value === undefined ? "missing" : String(value)
}

export function compareFacts(baseline, facts) {
  const errors = []
  for (const name of ["architecture", "productVersion", "buildVersion", "xcodeVersion", "xcodeBuild"]) {
    if (facts[name] !== baseline[name]) errors.push(`${name}: expected ${baseline[name]}, got ${actual(facts[name])}`)
  }
  if (facts.freeBytes < baseline.minimumFreeBytes) {
    errors.push(`freeBytes: expected at least ${baseline.minimumFreeBytes}, got ${actual(facts.freeBytes)}`)
  }
  if (!baseline.allowedRunnerNames.includes(facts.runnerName)) {
    errors.push(`runnerName: expected one of ${baseline.allowedRunnerNames.join(", ")}, got ${actual(facts.runnerName)}`)
  }
  if (!baseline.allowedConsoleUsers.includes(facts.consoleUser)) {
    errors.push(`consoleUser: expected one of ${baseline.allowedConsoleUsers.join(", ")}, got ${actual(facts.consoleUser)}`)
  }
  if (facts.developerModeEnabled !== true) errors.push(`developerModeEnabled: expected true, got ${actual(facts.developerModeEnabled)}`)
  if (facts.runnerOs !== "macOS") errors.push(`runnerOs: expected macOS, got ${actual(facts.runnerOs)}`)
  if (facts.runnerArch !== "ARM64") errors.push(`runnerArch: expected ARM64, got ${actual(facts.runnerArch)}`)
  const serviceCount = Array.isArray(facts.activeRunnerServices) ? facts.activeRunnerServices.length : 0
  if (serviceCount !== 1) errors.push(`active runner service count: expected 1, got ${serviceCount}`)
  return errors.sort()
}

function command(file, args) {
  return execFileSync(file, args, { encoding: "utf8" }).trim()
}

function freeBytes(directory) {
  const columns = command("/bin/df", ["-kP", directory]).split("\n").at(-1).trim().split(/\s+/)
  return Number(columns[3]) * 1024
}

function activeRunnerServices() {
  return command("/bin/launchctl", ["list"]).split("\n")
    .map(line => line.trim().split(/\s+/).at(-1))
    .filter(name => name.startsWith("actions.runner."))
    .sort()
}

export function collectFacts(directory = process.cwd()) {
  const xcode = command("/usr/bin/xcodebuild", ["-version"]).split("\n")
  return {
    hostname: os.hostname(),
    architecture: command("/usr/bin/uname", ["-m"]),
    productVersion: command("/usr/bin/sw_vers", ["-productVersion"]),
    buildVersion: command("/usr/bin/sw_vers", ["-buildVersion"]),
    xcodeVersion: xcode.find(line => line.startsWith("Xcode "))?.slice("Xcode ".length),
    xcodeBuild: xcode.find(line => line.startsWith("Build version "))?.slice("Build version ".length),
    consoleUser: command("/usr/bin/stat", ["-f", "%Su", "/dev/console"]),
    developerModeEnabled: /currently enabled/i.test(command("/usr/sbin/DevToolsSecurity", ["-status"])),
    freeBytes: freeBytes(directory),
    runnerName: process.env.RUNNER_NAME,
    runnerOs: process.env.RUNNER_OS,
    runnerArch: process.env.RUNNER_ARCH,
    activeRunnerServices: activeRunnerServices()
  }
}

function parseArguments(argv) {
  const options = {}
  for (let index = 0; index < argv.length; index += 1) {
    const name = argv[index]
    const value = argv[index + 1]
    if (!["--baseline", "--output", "--facts"].includes(name) || !value || value.startsWith("--")) {
      throw new Error("usage: --baseline PATH --output PATH [--facts FIXTURE_PATH]")
    }
    options[name.slice(2)] = value
    index += 1
  }
  if (!options.baseline || !options.output) throw new Error("usage: --baseline PATH --output PATH [--facts FIXTURE_PATH]")
  return options
}

function readJson(file) {
  return JSON.parse(fs.readFileSync(file, "utf8"))
}

function writeReceipt(output, facts, errors) {
  const receipt = { schemaVersion: 1, status: errors.length === 0 ? "healthy" : "drift", facts, errors }
  fs.writeFileSync(output, `${JSON.stringify(receipt, null, 2)}\n`)
}

function main() {
  const options = parseArguments(process.argv.slice(2))
  const baseline = readJson(options.baseline)
  const facts = options.facts ? readJson(options.facts) : collectFacts()
  const errors = compareFacts(baseline, facts)
  writeReceipt(options.output, facts, errors)
  if (errors.length > 0) process.exitCode = 2
}

if (import.meta.url === `file://${process.argv[1]}`) {
  try {
    main()
  } catch (error) {
    console.error(error.message)
    process.exitCode = 1
  }
}
