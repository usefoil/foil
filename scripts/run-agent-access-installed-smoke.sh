#!/usr/bin/env bash
set -euo pipefail

repository_root="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$repository_root"

usage() {
  cat <<'EOF'
Usage: scripts/run-agent-access-installed-smoke.sh

Builds Foil and Foil Dev unless FOIL_APP_PATH and FOIL_DEV_APP_PATH are set,
copies both signed app bundles into a temporary install directory, and proves:
  - both bundle signatures and identities are valid;
  - every documented Agent Access operation works over real Unix-socket curl;
  - no remote apply route exists and a rejected attempt leaves state byte-identical;
  - Foil and Foil Dev use separate sockets, catalogs, and proposal stores;
  - turning Agent Access off removes each socket without changing catalog/proposal bytes;
  - proposal content is absent from diagnostics and status responses.

Set AGENT_ACCESS_SMOKE_ARTIFACT_DIR to retain evidence at an explicit path. The
directory must not already exist. KEEP_AGENT_ACCESS_SMOKE_ARTIFACTS=1 retains the
default temporary evidence directory.

Set AGENT_ACCESS_AD_HOC_SIGNING=1 on a clean machine without a signing identity.
Xcode will ad-hoc sign and seal the Debug bundles before strict verification.

This harness uses DEBUG-only isolated-state and shutdown controls. It does not
claim notarized Release-artifact proof; use the Notarized QA Build and installed
production QA workflows for that boundary.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi
if [[ $# -ne 0 ]]; then
  usage >&2
  exit 2
fi

if [[ "${REQUIRE_NOTARIZATION:-0}" == "1" ]]; then
  echo "error: REQUIRE_NOTARIZATION is unsupported because this smoke uses DEBUG-only controls" >&2
  echo "Use the Notarized QA Build and installed production QA workflows instead." >&2
  exit 2
fi

if [[ "${AGENT_ACCESS_AD_HOC_SIGNING:-0}" != "0" && "${AGENT_ACCESS_AD_HOC_SIGNING:-0}" != "1" ]]; then
  echo "error: AGENT_ACCESS_AD_HOC_SIGNING must be 0 or 1" >&2
  exit 2
fi

requested_artifact_dir="${AGENT_ACCESS_SMOKE_ARTIFACT_DIR:-}"
if [[ -n "$requested_artifact_dir" ]]; then
  case "$requested_artifact_dir" in
    /*) smoke_root="$requested_artifact_dir" ;;
    *) smoke_root="$repository_root/$requested_artifact_dir" ;;
  esac
  if [[ -e "$smoke_root" ]]; then
    echo "error: AGENT_ACCESS_SMOKE_ARTIFACT_DIR already exists: $smoke_root" >&2
    exit 2
  fi
  mkdir -p "$smoke_root"
else
  smoke_root="$(mktemp -d /tmp/foil-agent-access-installed.XXXXXX)"
fi
install_root="$smoke_root/Applications"
production_runtime="$smoke_root/production"
development_runtime="$smoke_root/development"
production_tmp="$production_runtime/tmp"
development_tmp="$development_runtime/tmp"
production_state="$production_runtime/state"
development_state="$development_runtime/state"
production_control="$production_runtime/disable.control"
development_control="$development_runtime/disable.control"
production_log="$production_runtime/app.log"
development_log="$development_runtime/app.log"
production_pid=""
development_pid=""

mkdir -p "$install_root" "$production_tmp" "$development_tmp" "$production_state" "$development_state"

cleanup() {
  local status=$?
  for pid in "$production_pid" "$development_pid"; do
    if [[ -n "$pid" ]] && kill -0 "$pid" >/dev/null 2>&1; then
      kill "$pid" >/dev/null 2>&1 || true
      wait "$pid" >/dev/null 2>&1 || true
    fi
  done
  if [[ $status -ne 0 ]]; then
    echo "Agent Access installed smoke failed; artifacts retained at $smoke_root" >&2
    for log in "$production_log" "$development_log"; do
      if [[ -f "$log" ]]; then
        echo "--- ${log##*/} ---" >&2
        tail -40 "$log" >&2 || true
      fi
    done
  elif [[ "${KEEP_AGENT_ACCESS_SMOKE_ARTIFACTS:-0}" == "1" || -n "$requested_artifact_dir" ]]; then
    echo "artifacts=$smoke_root"
  else
    rm -rf "$smoke_root"
  fi
}
trap cleanup EXIT
trap 'exit 130' HUP INT TERM

build_setting() {
  local scheme=$1
  local key=$2
  xcodebuild -scheme "$scheme" -configuration Debug -destination 'platform=macOS' -showBuildSettings 2>/dev/null \
    | awk -v key="$key" '$1 == key && $2 == "=" { value=$3 } END { print value }'
}

source_foil_app="${FOIL_APP_PATH:-}"
source_dev_app="${FOIL_DEV_APP_PATH:-}"
build_apps() {
  if [[ "${AGENT_ACCESS_AD_HOC_SIGNING:-0}" == "1" ]]; then
    make "$@" 'SIGNING_FLAGS=CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=YES CODE_SIGN_STYLE=Manual ENABLE_HARDENED_RUNTIME=NO'
  else
    make "$@"
  fi
}

if [[ -z "$source_foil_app" && -z "$source_dev_app" ]]; then
  build_apps build build-dev
  source_foil_app="$(build_setting Foil BUILT_PRODUCTS_DIR)/Foil.app"
  source_dev_app="$(build_setting FoilDev BUILT_PRODUCTS_DIR)/Foil Dev.app"
elif [[ -z "$source_foil_app" ]]; then
  build_apps build
  source_foil_app="$(build_setting Foil BUILT_PRODUCTS_DIR)/Foil.app"
elif [[ -z "$source_dev_app" ]]; then
  build_apps build-dev
  source_dev_app="$(build_setting FoilDev BUILT_PRODUCTS_DIR)/Foil Dev.app"
fi

for source_app in "$source_foil_app" "$source_dev_app"; do
  if [[ ! -d "$source_app" ]]; then
    echo "error: app bundle not found: $source_app" >&2
    exit 1
  fi
done

installed_foil_app="$install_root/Foil.app"
installed_dev_app="$install_root/Foil Dev.app"
/usr/bin/ditto "$source_foil_app" "$installed_foil_app"
/usr/bin/ditto "$source_dev_app" "$installed_dev_app"

verify_bundle() {
  local app=$1
  local expected_identifier=$2
  /usr/bin/codesign --verify --deep --strict --verbose=2 "$app"
  local actual_identifier
  actual_identifier=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist")
  if [[ "$actual_identifier" != "$expected_identifier" ]]; then
    echo "error: expected $expected_identifier, found $actual_identifier in $app" >&2
    exit 1
  fi
}

verify_bundle "$installed_foil_app" "com.neonwatty.Foil"
verify_bundle "$installed_dev_app" "com.neonwatty.Foil.Dev"

production_socket="$production_state/AgentAccess/agent-v1.sock"
development_socket="$development_state/AgentAccess/agent-v1.sock"
production_store="$production_state/AgentAccess/agent-vocabulary-proposals-v1.json"
development_store="$development_state/AgentAccess/agent-vocabulary-proposals-v1.json"
production_catalog="$production_state/LocalCorrections/vocabulary-catalog-v2.json"
development_catalog="$development_state/LocalCorrections/vocabulary-catalog-v2.json"
production_diagnostics="$production_tmp/Foil/TestDiagnostics/foil.log"
development_diagnostics="$development_tmp/Foil/TestDiagnostics/foil.log"

launch_smoke_app() {
  local binary=$1
  local runtime_tmp=$2
  local state_root=$3
  local control_file=$4
  local log_file=$5
  TMPDIR="$runtime_tmp/" \
  FOIL_MANAGED_LOCAL_ACCEPTANCE_ROOT="$state_root" \
  FOIL_AGENT_ACCESS_SMOKE_CONTROL_FILE="$control_file" \
    "$binary" \
      --ui-testing \
      --managed-local-gui-acceptance \
      --reset-defaults \
      --agent-access-installed-smoke \
      --seed-agent-access-enabled >"$log_file" 2>&1 &
  echo $!
}

production_pid=$(launch_smoke_app "$installed_foil_app/Contents/MacOS/Foil" "$production_tmp" "$production_state" "$production_control" "$production_log")
development_pid=$(launch_smoke_app "$installed_dev_app/Contents/MacOS/Foil Dev" "$development_tmp" "$development_state" "$development_control" "$development_log")

wait_for_socket() {
  local socket=$1
  local pid=$2
  for _ in {1..120}; do
    if [[ -S "$socket" ]]; then return 0; fi
    if ! kill -0 "$pid" >/dev/null 2>&1; then
      echo "error: app process $pid exited before creating $socket" >&2
      return 1
    fi
    sleep 0.1
  done
  echo "error: socket did not appear: $socket" >&2
  return 1
}

wait_for_socket "$production_socket" "$production_pid"
wait_for_socket "$development_socket" "$development_pid"
if [[ "$production_socket" == "$development_socket" ]]; then
  echo "error: Foil and Foil Dev resolved the same Agent Access socket" >&2
  exit 1
fi

curl_get() {
  local socket=$1
  local path=$2
  local output=$3
  /usr/bin/curl --silent --show-error --fail-with-body --connect-timeout 1 --max-time 12 \
    --unix-socket "$socket" "http://foil$path" >"$output"
}

curl_post() {
  local socket=$1
  local path=$2
  local request=$3
  local output=$4
  /usr/bin/curl --silent --show-error --fail-with-body --connect-timeout 1 --max-time 12 \
    --unix-socket "$socket" -H 'Content-Type: application/json' --data-binary "@$request" \
    "http://foil$path" >"$output"
}

curl_post_status() {
  local socket=$1
  local path=$2
  local request=$3
  local output=$4
  /usr/bin/curl --silent --show-error --connect-timeout 1 --max-time 12 \
    --unix-socket "$socket" -H 'Content-Type: application/json' --data-binary "@$request" \
    --output "$output" --write-out '%{http_code}' "http://foil$path"
}

run_id="$$-$(date +%s)"
diagnostic_canary="agent-diagnostic-canary-$run_id"
production_request="$smoke_root/production-proposal.json"
development_request="$smoke_root/development-proposal.json"
preview_request="$smoke_root/preview.json"

cat >"$preview_request" <<'JSON'
{"corrections":[{"spoken_forms":["super base","Superbase"],"replacement":"Supabase"},{"spoken_forms":["codecs"],"replacement":"Codex"}]}
JSON
cat >"$production_request" <<JSON
{"schema_version":1,"request_id":"installed-production-$run_id","scope":{"kind":"global","id":"global"},"corrections":[{"spoken_forms":["super base","Superbase"],"replacement":"Supabase","note":"$diagnostic_canary"},{"spoken_forms":["codecs"],"replacement":"Codex"}]}
JSON
cat >"$development_request" <<JSON
{"schema_version":1,"request_id":"installed-development-$run_id","scope":{"kind":"global","id":"global"},"corrections":[{"spoken_forms":["foil dev spoken $run_id"],"replacement":"FoilDevWritten$run_id","note":"development-only"}]}
JSON

production_instructions="$smoke_root/production-instructions.json"
production_openapi="$smoke_root/production-openapi.json"
production_scopes="$smoke_root/production-scopes.json"
production_vocabulary="$smoke_root/production-vocabulary.json"
production_preview="$smoke_root/production-preview.json"
production_proposal="$smoke_root/production-proposal-response.json"
development_instructions="$smoke_root/development-instructions.json"
development_proposal="$smoke_root/development-proposal-response.json"

curl_get "$production_socket" /v1/instructions "$production_instructions"
curl_get "$production_socket" /v1/openapi.json "$production_openapi"
curl_get "$production_socket" /v1/vocabulary/scopes "$production_scopes"
curl_get "$production_socket" /v1/vocabulary "$production_vocabulary"
curl_post "$production_socket" /v1/vocabulary/preview "$preview_request" "$production_preview"
curl_post "$production_socket" /v1/vocabulary/proposals "$production_request" "$production_proposal"
curl_get "$development_socket" /v1/instructions "$development_instructions"
curl_post "$development_socket" /v1/vocabulary/proposals "$development_request" "$development_proposal"

production_proposal_id=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["proposal_id"])' "$production_proposal")
development_proposal_id=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["proposal_id"])' "$development_proposal")
production_status="$smoke_root/production-status.json"
development_status="$smoke_root/development-status.json"
curl_get "$production_socket" "/v1/vocabulary/proposals/$production_proposal_id" "$production_status"
curl_get "$development_socket" "/v1/vocabulary/proposals/$development_proposal_id" "$development_status"

python3 - "$production_instructions" "$production_openapi" "$production_scopes" "$production_vocabulary" "$production_preview" "$production_proposal" "$production_status" "$production_socket" "$production_proposal_id" <<'PY'
import json
import pathlib
import sys

instructions, openapi, scopes, vocabulary, preview, proposal, status = [
    json.load(open(path)) for path in sys.argv[1:8]
]
socket, proposal_id = sys.argv[8:10]
required = {
    "get_instructions", "get_openapi", "list_vocabulary_scopes", "list_vocabulary",
    "preview_vocabulary_corrections", "propose_vocabulary_corrections",
    "get_vocabulary_proposal_status",
}
assert set(instructions["available_operations"]) == required
assert socket in instructions["bootstrap_command"]
assert openapi["openapi"] == "3.1.0"
assert set(openapi["paths"]) == {
    "/v1/instructions", "/v1/openapi.json", "/v1/vocabulary/scopes",
    "/v1/vocabulary", "/v1/vocabulary/preview", "/v1/vocabulary/proposals",
    "/v1/vocabulary/proposals/{proposal_id}",
}
assert isinstance(scopes["scopes"], list)
assert isinstance(vocabulary["local_corrections_enabled"], bool)
assert isinstance(vocabulary["terms"], list)
assert isinstance(vocabulary["corrections"], list)
assert preview["valid"] is True, preview
assert [item["replacement"] for item in preview["normalized_corrections"]] == ["Supabase", "Codex"]
assert proposal["proposal_id"] == proposal_id
assert proposal["state"] == "pending"
assert proposal["replayed"] is False
assert status["proposal_id"] == proposal_id
assert status["state"] == "pending"
status_text = pathlib.Path(sys.argv[7]).read_text()
for forbidden in ("super base", "Superbase", "Supabase", "codecs", "Codex", "agent-diagnostic-canary"):
    assert forbidden not in status_text, forbidden
PY

for required_file in "$production_store" "$development_store" "$production_catalog" "$development_catalog"; do
  if [[ ! -f "$required_file" ]]; then
    echo "error: expected isolated state file: $required_file" >&2
    exit 1
  fi
done

denied_apply_request="$smoke_root/denied-remote-apply-request.json"
denied_apply_response="$smoke_root/denied-remote-apply-response.json"
printf '{"proposal_id":"%s"}\n' "$production_proposal_id" >"$denied_apply_request"
denied_apply_store_hash=$(shasum -a 256 "$production_store" | awk '{print $1}')
denied_apply_catalog_hash=$(shasum -a 256 "$production_catalog" | awk '{print $1}')
denied_apply_status=$(curl_post_status \
  "$production_socket" "/v1/vocabulary/apply" "$denied_apply_request" "$denied_apply_response")
if [[ "$denied_apply_status" != "404" ]]; then
  echo "error: nonexistent remote apply route returned HTTP $denied_apply_status instead of 404" >&2
  exit 1
fi
python3 - "$denied_apply_response" <<'PY'
import json
import sys

response = json.load(open(sys.argv[1]))
assert response["error"]["code"] == "route_not_found", response
PY
[[ "$denied_apply_store_hash" == "$(shasum -a 256 "$production_store" | awk '{print $1}')" ]]
[[ "$denied_apply_catalog_hash" == "$(shasum -a 256 "$production_catalog" | awk '{print $1}')" ]]

python3 - "$production_store" "$development_store" "$production_proposal_id" "$development_proposal_id" "$run_id" <<'PY'
import json
import pathlib
import sys

production_path, development_path, production_id, development_id, run_id = sys.argv[1:]
production_text = pathlib.Path(production_path).read_text()
development_text = pathlib.Path(development_path).read_text()
assert production_id in production_text and development_id not in production_text
assert development_id in development_text and production_id not in development_text
assert "super base" in production_text and f"foil dev spoken {run_id}" not in production_text
assert f"foil dev spoken {run_id}" in development_text and "super base" not in development_text
PY

if [[ "$(stat -f '%Lp' "$production_store")" != "600" || "$(stat -f '%Lp' "$development_store")" != "600" ]]; then
  echo "error: proposal stores are not owner-only 0600 files" >&2
  exit 1
fi

production_store_hash=$(shasum -a 256 "$production_store" | awk '{print $1}')
development_store_hash=$(shasum -a 256 "$development_store" | awk '{print $1}')
production_catalog_hash=$(shasum -a 256 "$production_catalog" | awk '{print $1}')
development_catalog_hash=$(shasum -a 256 "$development_catalog" | awk '{print $1}')

printf 'disable\n' >"$production_control"
printf 'disable\n' >"$development_control"

wait_for_removal() {
  local path=$1
  for _ in {1..100}; do
    if [[ ! -e "$path" ]]; then return 0; fi
    sleep 0.1
  done
  echo "error: Agent Access artifact remained after disable: $path" >&2
  return 1
}

wait_for_removal "$production_socket"
wait_for_removal "$development_socket"

python3 - "$production_state/AgentAccess/.agent-v1.lock" "$development_state/AgentAccess/.agent-v1.lock" <<'PY'
import fcntl
import os
import stat
import sys

for path in sys.argv[1:]:
    descriptor = os.open(path, os.O_RDWR | os.O_NOFOLLOW)
    try:
        assert stat.S_IMODE(os.fstat(descriptor).st_mode) == 0o600
        fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
        fcntl.flock(descriptor, fcntl.LOCK_UN)
    finally:
        os.close(descriptor)
PY

if /usr/bin/curl --silent --show-error --connect-timeout 1 --max-time 1 --unix-socket "$production_socket" http://foil/v1/instructions >/dev/null 2>&1; then
  echo "error: production Agent Access remained reachable after disable" >&2
  exit 1
fi

[[ "$production_store_hash" == "$(shasum -a 256 "$production_store" | awk '{print $1}')" ]]
[[ "$development_store_hash" == "$(shasum -a 256 "$development_store" | awk '{print $1}')" ]]
[[ "$production_catalog_hash" == "$(shasum -a 256 "$production_catalog" | awk '{print $1}')" ]]
[[ "$development_catalog_hash" == "$(shasum -a 256 "$development_catalog" | awk '{print $1}')" ]]

for diagnostic_file in "$production_diagnostics" "$development_diagnostics"; do
  if [[ -f "$diagnostic_file" ]] && grep -Fq "$diagnostic_canary" "$diagnostic_file"; then
    echo "error: proposal content leaked into diagnostics: $diagnostic_file" >&2
    exit 1
  fi
done

receipt="$smoke_root/receipt.txt"
{
  echo "status=pass"
  echo "bundles=Foil,Foil Dev"
  echo "signatures=verified"
  echo "socket_isolation=verified"
  echo "proposal_store_isolation=verified"
  echo "copied_command_flow=instructions,openapi,scopes,vocabulary,preview,submit,status"
  echo "remote_apply=absent,request-rejected-404,catalog-and-proposals-byte-identical"
  echo "disable_cleanup=socket-removed,lock-released,catalog-and-proposals-byte-identical"
  echo "diagnostic_content_leak=absent"
  echo "notarization=not-claimed-debug-controls-only"
} | tee "$receipt"
