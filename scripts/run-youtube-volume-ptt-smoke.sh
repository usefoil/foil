#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: scripts/run-youtube-volume-ptt-smoke.sh [--dry-run] [--check-sampler]

Guided local smoke for the YouTube/headphones push-to-talk volume issue.

Normal mode prompts the operator to:
  1. Start YouTube playback in Chrome.
  2. Confirm Foil is running with the default/recommended input path.
  3. Hold push-to-talk while the script samples macOS output volume.
  4. Release push-to-talk for the after samples.

The script does not press keys, control Chrome, quit apps, change volume, change
audio devices, or reset permissions. It writes evidence under /tmp.

Environment:
  FOIL_LOG_PATH       Override diagnostic log path.
  SAMPLE_COUNT        Samples per phase. Default: 5.
  SAMPLE_INTERVAL     Seconds between samples. Default: 1.
  ARTIFACT_DIR        Override output directory.
  VOLUME_SAMPLER_CMD  Override output-volume sampler command. It must print one
                      volume value and must not mutate volume, devices, apps, or
                      permissions.
USAGE
}

dry_run=false
check_sampler=false
for arg in "$@"; do
  case "$arg" in
    --dry-run)
      dry_run=true
      ;;
    --check-sampler)
      check_sampler=true
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "error: unknown argument: $arg" >&2
      usage >&2
      exit 2
      ;;
  esac
done

sample_count="${SAMPLE_COUNT:-5}"
sample_interval="${SAMPLE_INTERVAL:-1}"
timestamp="$(date +%Y%m%d-%H%M%S)"
artifact_dir="${ARTIFACT_DIR:-/tmp/foil-youtube-volume-ptt-smoke-${timestamp}}"
log_path="${FOIL_LOG_PATH:-$HOME/Library/Application Support/Foil/Diagnostics/foil.log}"
summary_path="${artifact_dir}/summary.md"
samples_path="${artifact_dir}/volume-samples.tsv"
diagnostics_path="${artifact_dir}/foil-diagnostics-tail.log"

if [[ "$dry_run" == true ]]; then
  cat <<DRYRUN
dry_run=true
artifact_dir=${artifact_dir}
summary_path=${summary_path}
samples_path=${samples_path}
diagnostics_path=${diagnostics_path}
foil_log_path=${log_path}
sample_count=${sample_count}
sample_interval=${sample_interval}
actions=none
DRYRUN
  exit 0
fi

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "error: required command not found: $1" >&2
    exit 1
  fi
}

read_output_volume() {
  local output
  if [[ -n "${VOLUME_SAMPLER_CMD:-}" ]]; then
    if output="$(eval "$VOLUME_SAMPLER_CMD" 2>&1)"; then
      printf '%s\n' "$output"
      return 0
    fi

    cat >&2 <<OVERRIDE_ERROR
error: VOLUME_SAMPLER_CMD failed.
command:
${VOLUME_SAMPLER_CMD}
output:
${output}
OVERRIDE_ERROR
    return 1
  fi

  if output="$(/usr/bin/osascript -e 'output volume of (get volume settings)' 2>&1)"; then
    printf '%s\n' "$output"
    return 0
  fi

  cat >&2 <<SAMPLER_ERROR
error: could not read macOS output volume with Standard Additions.
osascript output:
${output}

Run this smoke from a desktop Terminal session that can access macOS audio
state, or set up an alternate sampler before treating the live smoke as proof.
SAMPLER_ERROR
  return 1
}

if [[ "$check_sampler" == true ]]; then
  read_output_volume
  exit $?
fi

sample_phase() {
  local phase="$1"
  local count="$2"
  local interval="$3"
  local i volume now

  for ((i = 1; i <= count; i += 1)); do
    now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    volume="$(read_output_volume)"
    printf '%s\t%s\t%s\t%s\n' "$phase" "$i" "$now" "$volume" | tee -a "$samples_path"
    sleep "$interval"
  done
}

prompt_enter() {
  local message="$1"
  printf '\n%s\n' "$message"
  printf 'Press Return to continue. '
  read -r _
}

require_command osascript
require_command date
require_command tail
require_command grep

mkdir -p "$artifact_dir"
printf 'phase\tindex\tutc\toutput_volume\n' > "$samples_path"

cat > "$summary_path" <<SUMMARY
# YouTube Volume PTT Smoke

- Started UTC: $(date -u +%Y-%m-%dT%H:%M:%SZ)
- Artifact Dir: ${artifact_dir}
- Foil Log Path: ${log_path}
- Sample Count: ${sample_count}
- Sample Interval Seconds: ${sample_interval}
- Volume Sampler: ${VOLUME_SAMPLER_CMD:-/usr/bin/osascript -e 'output volume of (get volume settings)'}

## Operator Setup

- Play YouTube audio in Chrome.
- Use headphones/AirPods matching the reported issue.
- Ensure Foil is running.
- Use the default/recommended Recording input path unless intentionally testing an alternate row.
- Do not change system volume during the sample window.

## Result

- Before/During/After samples: volume-samples.tsv
- Foil diagnostic tail: foil-diagnostics-tail.log
SUMMARY

echo "Writing evidence to: $artifact_dir"
echo "Foil diagnostics path: $log_path"

prompt_enter "Setup: start YouTube playback in Chrome, connect the headphones, and confirm Foil is running."
sample_phase "before" "$sample_count" "$sample_interval"

prompt_enter "Start holding Foil push-to-talk now. Keep holding through the during samples."
sample_phase "during" "$sample_count" "$sample_interval"

prompt_enter "Release Foil push-to-talk now, then continue for after samples."
sample_phase "after" "$sample_count" "$sample_interval"

if [[ -f "$log_path" ]]; then
  tail -n 300 "$log_path" \
    | grep -E 'AudioRecorder:|RecordingController|otherAudio:|browserMediaControl:|AppDelegate: recordingController' \
    > "$diagnostics_path" || true
else
  printf 'Foil diagnostics log not found at %s\n' "$log_path" > "$diagnostics_path"
fi

cat <<DONE

Smoke capture complete.
Samples: ${samples_path}
Diagnostics: ${diagnostics_path}
Summary: ${summary_path}

Review expectation:
  The default/recommended path should not show a before -> during output-volume jump.
  Foil diagnostics should include input policy and recording route lines for the PTT window.
DONE
