import assert from "node:assert/strict"
import fs from "node:fs"
import test from "node:test"

const read = file => fs.readFileSync(new URL(`../../../${file}`, import.meta.url), "utf8")
const patch = read("scripts/patches/whisper-server-managed-lifecycle.patch")
const added = patch.split("\n").filter(line => line.startsWith("+") && !line.startsWith("+++")).map(line => line.slice(1)).join("\n")

test("normal managed builds require signed, embedded precompiled shaders", () => {
  assert.match(read("scripts/build-managed-whisper-runtime.sh"), /-DFOIL_METAL_PRECOMPILE=ON/)
  assert.match(read("scripts/build-managed-whisper-runtime.sh"), /xcrun -sdk macosx metal --version/)
  assert.match(read("scripts/embed-managed-whisper-runtime.sh"), /otool -arch "\$architecture" -l "\$helper".*\n.*__foil_metallib/)
  assert.match(added, /\.section __DATA,__foil_metallib/)
  assert.match(added, /add_dependencies\(ggml-metal foil-metal-libraries\)/)
})

test("both GPU capability variants target the app's macOS 14 minimum", () => {
  assert.match(added, /foreach\(variant plain bf16\)/)
  assert.match(added, /-DGGML_METAL_HAS_BF16/)
  assert.match(added, /foreach\(src \$\{METALLIB_KERNEL_SOURCES\}\)/)
  assert.match(added, /-mmacosx-version-min=14\.0 -std=metal3\.1/)
  assert.match(added, /metallib \$\{FOIL_METAL_AIR_FILES\}/)
})

test("compiled libraries stay inside the helper and Metal 4's existing path stays separate", () => {
  assert.match(added, /if \(!ggml_metal_device_get_props\(dev\)->has_tensor\)/)
  assert.match(added, /has_bfloat/)
  assert.match(added, /newLibraryWithData:data error:&error/)
  assert.match(added, /res->single_library = true/)
  assert.doesNotMatch(added, /newLibraryWithURL|GGML_METAL_PATH_RESOURCES|std::getenv\("GGML/)
})

test("hosted proof requires real Metal transcription, not a CPU fallback", () => {
  const workflow = read(".github/workflows/ci.yml")
  assert.match(workflow, /FOIL_REQUIRE_PRECOMPILED_METAL: "1"/)
  assert.match(workflow, /test-managed-whisper-runtime\.sh --app UnitDerivedData\/Build\/Products\/Debug\/Foil\.app/)
  assert.match(read("scripts/test-managed-whisper-runtime.sh"), /raise 'Transcription did not use embedded precompiled Metal' unless precompiled_used/)
})
