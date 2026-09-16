#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
root="$PWD"
cache="${FOIL_MANAGED_RUNTIME_CACHE:-$root/.research/managed-runtime}"
lock="$root/scripts/managed-whisper-runtime.lock.json"
field() { ruby -rjson -e 'print JSON.parse(File.read(ARGV[0])).fetch(ARGV[1])' "$lock" "$1"; }
verify_hash() { test "$(shasum -a 256 "$1" | cut -d ' ' -f 1)" = "$2"; }
mkdir -p "$cache/tools" "$cache/source" "$cache/models" "$cache/output"
prepare_fixture() {
  local fixture="$cache/models/ggml-tiny.en.bin"
  if [[ ! -f "$fixture" ]] || ! verify_hash "$fixture" "$(field fixture_sha256)"; then
    local download
    download="$(mktemp "$cache/models/download.XXXXXX")"
    if ! curl -fL "$(field fixture_url)" -o "$download" || ! verify_hash "$download" "$(field fixture_sha256)"; then
      echo 'Managed model download failed integrity verification' >&2; return 1
    fi
    test "$(stat -f %z "$download")" = "$(field fixture_size)"
    mv "$download" "$fixture"
  fi
  verify_hash "$fixture" "$(field fixture_sha256)"
  test "$(stat -f %z "$fixture")" = "$(field fixture_size)"
}
if [[ "${1:-}" = --fixture-only ]]; then prepare_fixture; exit 0; fi
if [[ ! -f "$cache/tools/cmake.tar.gz" ]]; then
  curl -fL "$(field cmake_url)" -o "$cache/tools/cmake.tar.gz"
fi
verify_hash "$cache/tools/cmake.tar.gz" "$(field cmake_sha256)"
tool_dir="$(mktemp -d "$cache/tools/verified.XXXXXX")"
tar -xzf "$cache/tools/cmake.tar.gz" -C "$tool_dir"
cmake="$tool_dir/cmake-4.1.1-macos-universal/CMake.app/Contents/bin/cmake"
"$cmake" --version
source_commit="$(field source_commit)"
if [[ ! -d "$cache/source/upstream/.git" ]]; then
  git clone --no-checkout "$(field source_repository)" "$cache/source/upstream"
fi
git -C "$cache/source/upstream" cat-file -e "$source_commit^{commit}"
git -C "$cache/source/upstream" fsck --no-reflogs
source_dir="$(mktemp -d "$cache/source/build.XXXXXX")"
git clone --shared --no-checkout "$cache/source/upstream" "$source_dir"
git -C "$source_dir" checkout --detach "$source_commit"
git -C "$source_dir" apply "$root/scripts/patches/whisper-server-managed-lifecycle.patch"
for architecture in arm64 x86_64; do
  build_dir="$source_dir/build-$architecture"
  "$cmake" -S "$source_dir" -B "$build_dir" \
    -DCMAKE_POLICY_VERSION_MINIMUM=3.5 -DCMAKE_OSX_ARCHITECTURES="$architecture" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 -DBUILD_SHARED_LIBS=OFF -DGGML_STATIC=ON \
    -DGGML_NATIVE=OFF -DGGML_BACKEND_DL=OFF -DGGML_CPU=ON -DGGML_CCACHE=OFF \
    -DGGML_METAL=ON -DGGML_METAL_EMBED_LIBRARY=ON -DGGML_ACCELERATE=ON \
    -DGGML_OPENMP=OFF -DGGML_OPENMP_FETCH=OFF -DGGML_BLAS=OFF \
    -DGGML_CUDA=OFF -DGGML_MUSA=OFF -DGGML_HIP=OFF -DGGML_VULKAN=OFF \
    -DGGML_RPC=OFF -DGGML_SYCL=OFF -DGGML_OPENCL=OFF -DGGML_OPENVINO=OFF \
    -DGGML_WEBGPU=OFF -DGGML_CPU_KLEIDIAI=OFF -DGGML_LLAMAFILE=OFF \
    -DGGML_SSE42=OFF -DGGML_AVX=OFF -DGGML_AVX2=OFF -DGGML_BMI2=OFF \
    -DGGML_FMA=OFF -DGGML_F16C=OFF -DGGML_AVX512=OFF \
    -DWHISPER_BUILD_IS_DEV=OFF -DWHISPER_BUILD_TESTS=OFF \
    -DWHISPER_BUILD_SERVER=ON -DWHISPER_CURL=OFF -DWHISPER_COREML=OFF
  "$cmake" --build "$build_dir" --target whisper-server -j 4
done
lipo -create "$source_dir/build-arm64/bin/whisper-server" "$source_dir/build-x86_64/bin/whisper-server" -output "$cache/output/whisper-server"
ruby -rjson -rdigest -e '
  helper, lock, patch, output = ARGV
  File.write(output, JSON.pretty_generate({"schema"=>1, "source_commit"=>JSON.parse(File.read(lock)).fetch("source_commit"),
    "sha256"=>Digest::SHA256.file(helper).hexdigest, "patch_sha256"=>Digest::SHA256.file(patch).hexdigest,
    "architectures"=>["arm64", "x86_64"], "minimum_macos"=>"14.0"}) + "\n")
' "$cache/output/whisper-server" "$lock" "$root/scripts/patches/whisper-server-managed-lifecycle.patch" "$cache/output/runtime.json"
prepare_fixture
bash scripts/embed-managed-whisper-runtime.sh --audit "$cache/output"
