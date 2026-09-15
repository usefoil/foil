import fs from "node:fs"

const suite = "FoilUITests/FoilUITests"
const shards = ["a", "b", "c"]
const liveMicrophoneTest = "testLiveMicrophoneSmoke"
const fixtureTest = "testE2ETranscription"

export function discoverTests(source) {
  return [...source.matchAll(/^\s*func\s+(test[A-Za-z0-9_]+)\s*\(/gm)].map(match => match[1])
}

export function discoverEnumeratedTests(enumeration) {
  const tests = []
  const visit = value => {
    if (Array.isArray(value)) return value.forEach(visit)
    if (!value || typeof value !== "object") return
    if (typeof value.identifier === "string") {
      const match = value.identifier.match(/^FoilUITests\/FoilUITests\/(test[A-Za-z0-9_]+)\(\)$/)
      if (match) tests.push(match[1])
    }
    Object.values(value).forEach(visit)
  }
  visit(enumeration)
  return [...new Set(tests)].sort()
}

export function validateManifest(discovered, manifest) {
  const manifestShards = manifest.shards && typeof manifest.shards === "object" && !Array.isArray(manifest.shards)
    ? manifest.shards
    : {}
  const errors = []
  for (const shard of shards) {
    if (!Object.hasOwn(manifestShards, shard)) errors.push(`missing shard: ${shard}`)
    else if (!Array.isArray(manifestShards[shard])) errors.push(`invalid shard assignments: ${shard}`)
  }
  for (const shard of Object.keys(manifestShards)) {
    if (!shards.includes(shard)) errors.push(`unknown shard: ${shard}`)
  }
  const assigned = shards.flatMap(shard => Array.isArray(manifestShards[shard]) ? manifestShards[shard] : [])
  const special = Object.keys(manifest.specialTests)
  const excluded = Object.keys(manifest.excluded)
  for (const [name, definition] of Object.entries(manifest.specialTests)) {
    if (!shards.includes(definition?.shard)) errors.push(`invalid special-test shard: ${name} (${definition?.shard})`)
  }
  for (const name of new Set([...assigned, ...special])) {
    if ([...assigned, ...special].filter(item => item === name).length > 1) errors.push(`duplicate assignment: ${name}`)
    if (excluded.includes(name)) errors.push(`overlapping assignment and exclusion: ${name}`)
  }
  for (const name of [...assigned, ...special, ...excluded]) {
    if (!discovered.includes(name)) errors.push(`stale assignment: ${name}`)
  }
  for (const name of discovered) {
    if (![...assigned, ...special, ...excluded].includes(name)) errors.push(`unassigned test: ${name}`)
  }
  return [...new Set(errors)].sort()
}

function parseArguments(argv) {
  const options = {}
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index]
    if (!argument.startsWith("--")) throw new Error(`unexpected argument: ${argument}`)
    const name = argument.slice(2)
    const value = argv[index + 1]
    if (!value || value.startsWith("--")) throw new Error(`missing value for --${name}`)
    options[name] = value
    index += 1
  }
  return options
}

function readManifest(path) {
  return JSON.parse(fs.readFileSync(path, "utf8"))
}

function createManifest(discovered) {
  const manifest = {
    schemaVersion: 1,
    suite,
    shards: { a: [], b: [], c: [] },
    specialTests: {
      [fixtureTest]: { shard: "c", command: "make test-fixture-transcription-e2e" }
    },
    excluded: {
      [liveMicrophoneTest]: {
        reason: "requires a real microphone",
        workflow: ".github/workflows/live-microphone-qa.yml"
      }
    }
  }
  const ordinary = discovered.filter(name => name !== liveMicrophoneTest && name !== fixtureTest)
  ordinary.forEach((name, index) => manifest.shards[shards[index % shards.length]].push(name))
  return manifest
}

function audit(discovered, manifest) {
  const errors = validateManifest(discovered, manifest)
  const assigned = shards.flatMap(shard => Array.isArray(manifest.shards?.[shard]) ? manifest.shards[shard] : []).length + Object.keys(manifest.specialTests).length
  console.log(`${assigned} assigned, ${Object.keys(manifest.excluded).length} excluded, ${errors.length} errors`)
  errors.forEach(error => console.error(error))
  return errors.length === 0
}

function requireOption(options, name) {
  if (!options[name]) throw new Error(`--${name} is required`)
  return options[name]
}

function main() {
  const [command, ...argv] = process.argv.slice(2)
  const options = parseArguments(argv)

  if (command === "seed") {
    const sourcePath = requireOption(options, "source")
    const manifestPath = requireOption(options, "manifest")
    if (fs.existsSync(manifestPath)) throw new Error(`refusing to overwrite existing manifest: ${manifestPath}`)
    const manifest = createManifest(discoverTests(fs.readFileSync(sourcePath, "utf8")))
    fs.writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`)
    return
  }

  if (command === "check" || command === "check-built") {
    const manifest = readManifest(requireOption(options, "manifest"))
    const discovered = command === "check"
      ? discoverTests(fs.readFileSync(requireOption(options, "source"), "utf8"))
      : discoverEnumeratedTests(JSON.parse(fs.readFileSync(requireOption(options, "enumeration"), "utf8")))
    if (!audit(discovered, manifest)) process.exitCode = 1
    return
  }

  if (command === "selectors") {
    const manifest = readManifest(options.manifest || "scripts/ci/ui-test-shards.json")
    const shard = requireOption(options, "shard")
    if (!shards.includes(shard)) throw new Error(`unknown shard: ${shard}`)
    if (!Array.isArray(manifest.shards?.[shard])) throw new Error(`invalid shard assignments: ${shard}`)
    manifest.shards[shard].forEach(name => console.log(`-only-testing:${suite}/${name}`))
    return
  }

  throw new Error(`unknown command: ${command || "(none)"}`)
}

if (import.meta.url === `file://${process.argv[1]}`) {
  try {
    main()
  } catch (error) {
    console.error(error.message)
    process.exitCode = 1
  }
}
