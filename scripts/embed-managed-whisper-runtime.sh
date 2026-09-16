#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
root="$PWD"
cache="${FOIL_MANAGED_RUNTIME_CACHE:-$root/.research/managed-runtime}"
runtime_dir="$cache/output"
if [[ "${1:-}" != --audit ]]; then
  # Serialize cold builds from independent Xcode targets. Recheck after taking
  # the lock; a concurrent target may already have prepared the same cache.
  (
    mkdir -p "$cache"
    acquired=false
    for ((attempt=0; attempt<600; attempt++)); do
      if mkdir "$cache/.prepare-lock" 2>/dev/null; then acquired=true; break; fi
      sleep 1
    done
    if [[ "$acquired" != true ]]; then echo 'Timed out preparing managed runtime' >&2; exit 1; fi
    trap 'rmdir "$cache/.prepare-lock"' EXIT
    if ! bash "$root/scripts/embed-managed-whisper-runtime.sh" --audit "$runtime_dir" >/dev/null 2>&1; then
      FOIL_MANAGED_RUNTIME_CACHE="$cache" bash "$root/scripts/build-managed-whisper-runtime.sh"
    fi
    bash "$root/scripts/embed-managed-whisper-runtime.sh" --audit "$runtime_dir"
    if [[ "${1:-}" = --stage-test-model ]]; then
      fixture="$cache/models/ggml-tiny.en.bin"
      valid_fixture() {
        ruby -rjson -rdigest -e 'lock=JSON.parse(File.read(ARGV[1])); exit(File.file?(ARGV[0]) && File.size(ARGV[0]) == lock.fetch("fixture_size") && Digest::SHA256.file(ARGV[0]).hexdigest == lock.fetch("fixture_sha256") ? 0 : 1)' "$fixture" "$root/scripts/managed-whisper-runtime.lock.json"
      }
      if ! valid_fixture; then
        FOIL_MANAGED_RUNTIME_CACHE="$cache" bash "$root/scripts/build-managed-whisper-runtime.sh" --fixture-only
      fi
      valid_fixture
      : "${TARGET_BUILD_DIR:?}" "${UNLOCALIZED_RESOURCES_FOLDER_PATH:?}"
      mkdir -p "$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH"
      cp "$fixture" "$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/ggml-tiny.en.bin"
    fi
  )
  if [[ "${1:-}" = --stage-test-model ]]; then exit 0; fi
fi
if [[ "${1:-}" = --audit ]]; then runtime_dir="$2"; fi
helper="$runtime_dir/whisper-server"
manifest="$runtime_dir/runtime.json"
test -f "$helper"
test ! -L "$helper"
test -f "$manifest"
ruby -rjson -rdigest -e '
  helper, manifest, lock, patch = ARGV
  data = JSON.parse(File.read(manifest))
  abort "Invalid runtime provenance" unless data.fetch("schema") == 1 &&
    data.fetch("source_commit") == JSON.parse(File.read(lock)).fetch("source_commit") &&
    data.fetch("sha256") == Digest::SHA256.file(helper).hexdigest &&
    data.fetch("patch_sha256") == Digest::SHA256.file(patch).hexdigest &&
    data.fetch("architectures").sort == ["arm64", "x86_64"] && data.fetch("minimum_macos") == "14.0"
' "$helper" "$manifest" scripts/managed-whisper-runtime.lock.json scripts/patches/whisper-server-managed-lifecycle.patch
test "$(lipo -archs "$helper" | tr ' ' '\n' | sort | tr '\n' ' ')" = 'arm64 x86_64 '
for architecture in arm64 x86_64; do
  otool -arch "$architecture" -l "$helper" | awk '/LC_BUILD_VERSION/{found=1} found && /minos/{if ($2 != "14.0") exit 1; ok=1; exit} END {if (!ok) exit 1}'
  otool -arch "$architecture" -l "$helper" | /usr/bin/grep -q '__ggml_metallib'
  otool -arch "$architecture" -L "$helper" | tail -n +2 | while IFS= read -r dependency; do
    case "$dependency" in
      *'/System/Library/'*|*'/usr/lib/'*) ;;
      *) echo 'Non-system runtime dependency rejected' >&2; exit 1 ;;
    esac
  done
done
if [[ "${1:-}" = --audit ]]; then echo 'PASS: universal macOS 14 runtime provenance and dependencies'; exit 0; fi
: "${TARGET_BUILD_DIR:?}" "${CONTENTS_FOLDER_PATH:?}" "${EXPANDED_CODE_SIGN_IDENTITY:?}"
destination="$TARGET_BUILD_DIR/$CONTENTS_FOLDER_PATH/Helpers"
mkdir -p "$destination"
cp "$helper" "$destination/whisper-server"
chmod 755 "$destination/whisper-server"
codesign --force --options runtime --sign "$EXPANDED_CODE_SIGN_IDENTITY" "$destination/whisper-server"
codesign --verify --strict "$destination/whisper-server"
