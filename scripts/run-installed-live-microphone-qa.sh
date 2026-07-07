#!/usr/bin/env bash
set -euo pipefail

if [[ "${RUN_INSTALLED_LIVE_MICROPHONE_TESTS:-}" != "1" ]]; then
  echo "skip: set RUN_INSTALLED_LIVE_MICROPHONE_TESTS=1 to run installed live microphone QA"
  exit 0
fi

HOST="${HOST:-mm2}"
SSH="${SSH:-ssh}"
SSH_OPTS="${SSH_OPTS:--o BatchMode=yes -o AddressFamily=inet6}"
APP_PATH="${APP_PATH:-/Applications/Foil.app}"
EVIDENCE_DIR="${EVIDENCE_DIR:-/tmp/foil-installed-live-microphone-qa-$(date -u +%Y%m%dT%H%M%SZ)}"
LIVE_MICROPHONE_DURATION_SECONDS="${LIVE_MICROPHONE_DURATION_SECONDS:-4}"
LIVE_MICROPHONE_INPUT_ROUTE="${LIVE_MICROPHONE_INPUT_ROUTE:-system-default}"
LIVE_MICROPHONE_APPLE_VOICE_TEXT="${LIVE_MICROPHONE_APPLE_VOICE_TEXT:-Foil microphone test.}"
EXPECTED_BUNDLE_ID="${EXPECTED_BUNDLE_ID:-com.neonwatty.Foil}"
EXPECTED_VERSION="${EXPECTED_VERSION:-}"
EXPECTED_BUILD="${EXPECTED_BUILD:-}"
EXPECTED_SIGNING_IDENTITY="${EXPECTED_SIGNING_IDENTITY:-Developer ID Application: Mean Weasel LLC (B3A6AN2HA4)}"
KILL_EXISTING_FOIL="${KILL_EXISTING_FOIL:-1}"
REMOTE_OPEN="${REMOTE_OPEN:-/usr/bin/open}"
REMOTE_CODESIGN="${REMOTE_CODESIGN:-/usr/bin/codesign}"
REMOTE_SPCTL="${REMOTE_SPCTL:-/usr/sbin/spctl}"
REMOTE_PKILL="${REMOTE_PKILL:-/usr/bin/pkill}"
REMOTE_PLISTBUDDY="${REMOTE_PLISTBUDDY:-/usr/libexec/PlistBuddy}"

shell_quote() {
  local value="$1"
  printf "'%s'" "${value//\'/\'\\\'\'}"
}

ssh_opts_array=()
if [[ -n "${SSH_OPTS}" ]]; then
  # shellcheck disable=SC2206
  ssh_opts_array=( ${SSH_OPTS} )
fi

remote_command="env"
for assignment in \
  "REQUESTED_HOST=${HOST}" \
  "APP_PATH=${APP_PATH}" \
  "EVIDENCE_DIR=${EVIDENCE_DIR}" \
  "LIVE_MICROPHONE_DURATION_SECONDS=${LIVE_MICROPHONE_DURATION_SECONDS}" \
  "LIVE_MICROPHONE_INPUT_ROUTE=${LIVE_MICROPHONE_INPUT_ROUTE}" \
  "LIVE_MICROPHONE_APPLE_VOICE_TEXT=${LIVE_MICROPHONE_APPLE_VOICE_TEXT}" \
  "EXPECTED_BUNDLE_ID=${EXPECTED_BUNDLE_ID}" \
  "EXPECTED_VERSION=${EXPECTED_VERSION}" \
  "EXPECTED_BUILD=${EXPECTED_BUILD}" \
  "EXPECTED_SIGNING_IDENTITY=${EXPECTED_SIGNING_IDENTITY}" \
  "KILL_EXISTING_FOIL=${KILL_EXISTING_FOIL}" \
  "REMOTE_OPEN=${REMOTE_OPEN}" \
  "REMOTE_CODESIGN=${REMOTE_CODESIGN}" \
  "REMOTE_SPCTL=${REMOTE_SPCTL}" \
  "REMOTE_PKILL=${REMOTE_PKILL}" \
  "REMOTE_PLISTBUDDY=${REMOTE_PLISTBUDDY}"; do
  remote_command+=" ${assignment%%=*}=$(shell_quote "${assignment#*=}")"
done
remote_command+=" /bin/bash -s"

"${SSH}" "${ssh_opts_array[@]}" "${HOST}" "${remote_command}" <<'REMOTE_SCRIPT'
set -euo pipefail

RESULT_PATH="${EVIDENCE_DIR}/live-microphone-result.txt"
STDOUT_PATH="${EVIDENCE_DIR}/open-stdout.log"
STDERR_PATH="${EVIDENCE_DIR}/open-stderr.log"
SUMMARY_PATH="${EVIDENCE_DIR}/summary.txt"
MANIFEST_PATH="${EVIDENCE_DIR}/manifest.txt"

mkdir -p "${EVIDENCE_DIR}"
rm -f "${RESULT_PATH}" "${STDOUT_PATH}" "${STDERR_PATH}" "${SUMMARY_PATH}" "${MANIFEST_PATH}"

fail() {
  echo "error: $*" >&2
  exit 1
}

plist_read() {
  "${REMOTE_PLISTBUDDY}" -c "Print :$1" "${APP_PATH}/Contents/Info.plist"
}

receipt_value() {
  local key="$1"
  sed -n "s/^${key}=//p" "${RESULT_PATH}" | head -1
}

numeric_positive() {
  local value="$1"
  awk -v value="${value:-0}" 'BEGIN { exit !((value + 0) > 0) }'
}

if [[ ! -d "${APP_PATH}" ]]; then
  fail "installed app not found: ${APP_PATH}"
fi
if [[ ! -x "${APP_PATH}/Contents/MacOS/Foil" ]]; then
  fail "installed app executable missing: ${APP_PATH}/Contents/MacOS/Foil"
fi
open_help="$("${REMOTE_OPEN}" -h 2>&1 || true)"
if ! grep -q -- "--env" <<<"${open_help}"; then
  fail "LaunchServices open does not support --env on this host"
fi

bundle_id="$(plist_read CFBundleIdentifier)"
bundle_version="$(plist_read CFBundleShortVersionString)"
bundle_build="$(plist_read CFBundleVersion)"

if [[ "${bundle_id}" != "${EXPECTED_BUNDLE_ID}" ]]; then
  fail "expected bundle_id ${EXPECTED_BUNDLE_ID}, found ${bundle_id}"
fi
if [[ -n "${EXPECTED_VERSION}" && "${bundle_version}" != "${EXPECTED_VERSION}" ]]; then
  fail "expected version ${EXPECTED_VERSION}, found ${bundle_version}"
fi
if [[ -n "${EXPECTED_BUILD}" && "${bundle_build}" != "${EXPECTED_BUILD}" ]]; then
  fail "expected build ${EXPECTED_BUILD}, found ${bundle_build}"
fi

codesign_detail="$("${REMOTE_CODESIGN}" -dv "${APP_PATH}" 2>&1)"
"${REMOTE_CODESIGN}" --verify --deep --strict --verbose=2 "${APP_PATH}" >/dev/null 2>&1 \
  || fail "codesign verification failed for ${APP_PATH}"
spctl_detail="$("${REMOTE_SPCTL}" -a -vv -t open --context context:primary-signature "${APP_PATH}" 2>&1)"
if ! grep -Fq "accepted" <<<"${spctl_detail}" || ! grep -Fq "Notarized Developer ID" <<<"${spctl_detail}"; then
  fail "Gatekeeper did not accept ${APP_PATH} as Notarized Developer ID"
fi
if [[ -n "${EXPECTED_SIGNING_IDENTITY}" ]] \
  && ! grep -Fq "Authority=${EXPECTED_SIGNING_IDENTITY}" <<<"${codesign_detail}" \
  && ! grep -Fq "origin=${EXPECTED_SIGNING_IDENTITY}" <<<"${spctl_detail}"; then
  fail "expected signing identity ${EXPECTED_SIGNING_IDENTITY}"
fi

{
  echo "host=${REQUESTED_HOST}"
  echo "app_path=${APP_PATH}"
  echo "bundle_id=${bundle_id}"
  echo "bundle_version=${bundle_version}"
  echo "bundle_build=${bundle_build}"
  echo "expected_bundle_id=${EXPECTED_BUNDLE_ID}"
  echo "expected_version=${EXPECTED_VERSION}"
  echo "expected_build=${EXPECTED_BUILD}"
  echo "input_route=${LIVE_MICROPHONE_INPUT_ROUTE}"
  echo "duration_seconds=${LIVE_MICROPHONE_DURATION_SECONDS}"
  echo "evidence_dir=${EVIDENCE_DIR}"
  echo "result_path=${RESULT_PATH}"
  echo "stdout_path=${STDOUT_PATH}"
  echo "stderr_path=${STDERR_PATH}"
  date -u '+generated_at=%Y-%m-%dT%H:%M:%SZ'
} >"${MANIFEST_PATH}"

if [[ "${KILL_EXISTING_FOIL}" == "1" ]]; then
  "${REMOTE_PKILL}" -x Foil >/dev/null 2>&1 || true
  sleep 1
fi

"${REMOTE_OPEN}" -n -W -a "${APP_PATH}" \
  --env "FOIL_ENABLE_RELEASE_LIVE_MICROPHONE_SMOKE=1" \
  --env "LIVE_MICROPHONE_RESULT_PATH=${RESULT_PATH}" \
  --env "LIVE_MICROPHONE_DURATION_SECONDS=${LIVE_MICROPHONE_DURATION_SECONDS}" \
  --env "LIVE_MICROPHONE_INPUT_ROUTE=${LIVE_MICROPHONE_INPUT_ROUTE}" \
  --env "LIVE_MICROPHONE_APPLE_VOICE_TEXT=${LIVE_MICROPHONE_APPLE_VOICE_TEXT}" \
  --env "LIVE_MICROPHONE_SIGNING_IDENTITY=${EXPECTED_SIGNING_IDENTITY}" \
  -o "${STDOUT_PATH}" --stderr "${STDERR_PATH}" \
  --args --ui-testing --reset-defaults --seed-setup-ready --live-microphone-smoke &
open_pid=$!

for _ in $(seq 1 75); do
  if [[ -f "${RESULT_PATH}" ]] && grep -Eq '^status=(pass|fail)$' "${RESULT_PATH}"; then
    break
  fi
  sleep 1
done

if [[ "${KILL_EXISTING_FOIL}" == "1" ]]; then
  "${REMOTE_PKILL}" -x Foil >/dev/null 2>&1 || true
  wait "${open_pid}" 2>/dev/null || true
else
  kill "${open_pid}" 2>/dev/null || true
  wait "${open_pid}" 2>/dev/null || true
fi

result_exists="no"
[[ -f "${RESULT_PATH}" ]] && result_exists="yes"
gatekeeper_status="rejected"
grep -Fq "accepted" <<<"${spctl_detail}" && gatekeeper_status="accepted"

{
  echo "evidence_dir=${EVIDENCE_DIR}"
  echo "host=${REQUESTED_HOST}"
  echo "app_path=${APP_PATH}"
  echo "bundle_id=${bundle_id}"
  echo "bundle_version=${bundle_version}"
  echo "bundle_build=${bundle_build}"
  echo "gatekeeper_status=${gatekeeper_status}"
  echo "gatekeeper_detail=$(tr '\n' '|' <<<"${spctl_detail}")"
  echo "codesign_detail=$(tr '\n' '|' <<<"${codesign_detail}")"
  echo "result_exists=${result_exists}"
  echo "---result---"
  [[ -f "${RESULT_PATH}" ]] && cat "${RESULT_PATH}" || true
  echo "---stderr-tail---"
  [[ -f "${STDERR_PATH}" ]] && tail -120 "${STDERR_PATH}" || true
} | tee "${SUMMARY_PATH}"

[[ -f "${RESULT_PATH}" ]] || fail "installed live microphone QA produced no result file"

status="$(receipt_value status)"
permission="$(receipt_value microphone_permission_status)"
input_route="$(receipt_value input_route_request)"
apple_voice_started="$(receipt_value apple_voice_process_started)"
bytes="$(receipt_value bytes)"
level_peak="$(receipt_value level_peak)"
file_level_peak="$(receipt_value file_level_peak)"

[[ "${status}" == "pass" ]] || fail "status must be pass, found ${status:-<missing>}"
[[ "${permission}" == "authorized" ]] || fail "microphone_permission_status must be authorized, found ${permission:-<missing>}"
[[ "${input_route}" == "${LIVE_MICROPHONE_INPUT_ROUTE}" ]] || fail "input_route_request must be ${LIVE_MICROPHONE_INPUT_ROUTE}, found ${input_route:-<missing>}"
if [[ -n "${LIVE_MICROPHONE_APPLE_VOICE_TEXT}" ]]; then
  [[ "${apple_voice_started}" == "true" ]] || fail "apple_voice_process_started must be true, found ${apple_voice_started:-<missing>}"
fi
numeric_positive "${bytes}" || fail "bytes must be positive, found ${bytes:-<missing>}"
if ! numeric_positive "${level_peak}" && ! numeric_positive "${file_level_peak}"; then
  fail "level_peak or file_level_peak must be positive, found level_peak=${level_peak:-<missing>} file_level_peak=${file_level_peak:-<missing>}"
fi

echo "Installed live microphone QA passed."
echo "evidence_dir=${EVIDENCE_DIR}"
echo "result_path=${RESULT_PATH}"
REMOTE_SCRIPT
