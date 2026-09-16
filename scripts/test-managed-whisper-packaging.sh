#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p "$PWD/.research"
cache="$(mktemp -d "$PWD/.research/managed-packaging.XXXXXX")"
test -f scripts/embed-managed-whisper-runtime.sh
if [[ ! -f .research/managed-runtime/output/runtime.json ]]; then bash scripts/build-managed-whisper-runtime.sh; fi
bash scripts/embed-managed-whisper-runtime.sh --audit "$PWD/.research/managed-runtime/output"
mkdir -p "$cache/missing" "$cache/malformed"
if bash scripts/embed-managed-whisper-runtime.sh --audit "$cache/missing"; then
  echo 'FAIL: packaging accepted missing runtime' >&2; exit 1
fi
cp /usr/bin/true "$cache/malformed/whisper-server"
if bash scripts/embed-managed-whisper-runtime.sh --audit "$cache/malformed"; then
  echo 'FAIL: packaging accepted missing provenance' >&2; exit 1
fi
echo 'PASS: missing runtime and missing provenance rejected'
ruby - "$cache" "$PWD/.research/managed-runtime/output" <<'RUBY'
require 'json'
require 'digest'
require 'fileutils'
cache, source = ARGV
# Exercise the actual normal embedding entry point in a cold miniature checkout.
# Only the expensive pinned compiler build is replaced; audit and signing remain real.
cold = File.join(cache, 'cold-checkout')
FileUtils.mkdir_p(File.join(cold, 'scripts', 'patches'))
%w[embed-managed-whisper-runtime.sh managed-whisper-runtime.lock.json].each do |name|
  FileUtils.cp(File.join('scripts', name), File.join(cold, 'scripts', name))
end
FileUtils.cp('scripts/patches/whisper-server-managed-lifecycle.patch', File.join(cold, 'scripts', 'patches'))
File.write(File.join(cold, 'scripts', 'build-managed-whisper-runtime.sh'), <<~SH)
  #!/bin/bash
  set -euo pipefail
  if [[ "${1:-}" = --fixture-only ]]; then
    mkdir -p "$FOIL_MANAGED_RUNTIME_CACHE/models"
    cp "$FOIL_PACKAGING_TEST_FIXTURE" "$FOIL_MANAGED_RUNTIME_CACHE/models/ggml-tiny.en.bin"
    exit 0
  fi
  mkdir -p "$FOIL_MANAGED_RUNTIME_CACHE/output"
  cp "$FOIL_PACKAGING_TEST_SOURCE/whisper-server" "$FOIL_PACKAGING_TEST_SOURCE/runtime.json" "$FOIL_MANAGED_RUNTIME_CACHE/output/"
  echo prepared >> "$FOIL_MANAGED_RUNTIME_CACHE/prepared"
SH
env = {'FOIL_MANAGED_RUNTIME_CACHE'=>File.join(cold, 'generated-cache'),
       'FOIL_PACKAGING_TEST_SOURCE'=>source,
       'FOIL_PACKAGING_TEST_FIXTURE'=>File.expand_path('../models/ggml-tiny.en.bin', source),
       'TARGET_BUILD_DIR'=>File.join(cold, 'products'),
       'CONTENTS_FOLDER_PATH'=>'Fixture.app/Contents', 'EXPANDED_CODE_SIGN_IDENTITY'=>'-'}
embed = File.join(cold, 'scripts', 'embed-managed-whisper-runtime.sh')
raise 'Normal build failed to prepare a cold cache' unless system(env, 'bash', embed)
raise 'Cold preparation did not embed runtime' unless File.executable?(File.join(env['TARGET_BUILD_DIR'], env['CONTENTS_FOLDER_PATH'], 'Helpers', 'whisper-server'))
raise 'Warm normal build failed' unless system(env, 'bash', embed)
marker = File.join(env['FOIL_MANAGED_RUNTIME_CACHE'], 'prepared')
raise 'Warm cache unnecessarily rebuilt' unless File.readlines(marker).length == 1
unsigned_env = env.merge('TARGET_BUILD_DIR'=>File.join(cold, 'unsigned-products'),
                         'CODE_SIGNING_ALLOWED'=>'NO')
unsigned_env.delete('EXPANDED_CODE_SIGN_IDENTITY')
raise 'Unsigned Xcode build required a signing identity' unless system(unsigned_env, 'bash', embed)
unsigned_helper = File.join(unsigned_env['TARGET_BUILD_DIR'], unsigned_env['CONTENTS_FOLDER_PATH'], 'Helpers', 'whisper-server')
raise 'Unsigned Xcode build did not embed an executable runtime' unless File.executable?(unsigned_helper)
missing_identity_env = env.merge('TARGET_BUILD_DIR'=>File.join(cold, 'missing-identity-products'))
missing_identity_env.delete('EXPANDED_CODE_SIGN_IDENTITY')
raise 'Signing-enabled build accepted a missing identity' if system(missing_identity_env, 'bash', embed)
puts 'PASS: unsigned builds embed without an identity; signing-enabled builds still require one'
env['UNLOCALIZED_RESOURCES_FOLDER_PATH'] = 'FixtureTests.xctest/Contents/Resources'
raise 'Missing test model was not prepared' unless system(env, 'bash', embed, '--stage-test-model')
staged = File.join(env['TARGET_BUILD_DIR'], env['UNLOCALIZED_RESOURCES_FOLDER_PATH'], 'ggml-tiny.en.bin')
raise 'Test model staging changed bytes' unless Digest::SHA256.file(staged).hexdigest == '921e4cf8686fdd993dcd081a5da5b6c365bfde1162e72b08d75ac75289920b1f'
raise 'Normal app contains a test model' unless Dir.glob(File.join(env['TARGET_BUILD_DIR'], 'Fixture.app', '**', '*.bin')).empty?
File.open(File.join(env['FOIL_MANAGED_RUNTIME_CACHE'], 'output', 'whisper-server'), 'ab') { |f| f.write('corrupt') }
raise 'Invalid cache was not repaired' unless system(env, 'bash', embed)
raise 'Invalid cache bypassed preparation' unless File.readlines(marker).length == 2
File.write(File.join(cold, 'scripts', 'build-managed-whisper-runtime.sh'), "#!/bin/bash\nexit 0\n")
File.open(File.join(env['FOIL_MANAGED_RUNTIME_CACHE'], 'output', 'whisper-server'), 'ab') { |f| f.write('corrupt') }
raise 'Unrepaired cache was accepted' if system(env, 'bash', embed)
puts 'PASS: cold normal build self-prepares, warm cache reuses, corruption repairs, failed repair rejects'
%w[corrupt metadata thin malformed].each do |scenario|
  directory = File.join(cache, scenario)
  FileUtils.mkdir_p(directory)
  FileUtils.cp(File.join(source, 'whisper-server'), directory)
  manifest = JSON.parse(File.read(File.join(source, 'runtime.json')))
  helper = File.join(directory, 'whisper-server')
  case scenario
  when 'corrupt'
    File.open(helper, 'ab') { |f| f.write('unexpected') }
  when 'metadata'
    manifest['source_commit'] = '0' * 40
  when 'thin'
    raise 'Fixture thinning failed' unless system('/usr/bin/lipo', File.join(source, 'whisper-server'), '-thin', 'arm64', '-output', helper)
    manifest['sha256'] = Digest::SHA256.file(helper).hexdigest
  when 'malformed'
    File.binwrite(helper, 'not executable code')
    manifest['sha256'] = Digest::SHA256.file(helper).hexdigest
  end
  File.write(File.join(directory, 'runtime.json'), JSON.generate(manifest))
  raise "Packaging accepted #{scenario}" if system('bash', 'scripts/embed-managed-whisper-runtime.sh', '--audit', directory)
  puts "PASS: rejected #{scenario} runtime"
end
RUBY
