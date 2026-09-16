#!/usr/bin/env bash
# Disable inherited tracing before inspecting credentials or invoking the runner.
set +x
set -euo pipefail

fail() { printf 'bootstrap-foil-runner: %s\n' "$1" >&2; exit 1; }
usage() {
  printf '%s\n' 'usage: bootstrap-foil-runner.sh --runner-dir PATH --runner-name foil-mm1|foil-mm2|foil-mm3 [--repo-url https://github.com/usefoil/foil] [--dry-run]'
}

runner_dir=''
runner_name=''
repo_url='https://github.com/usefoil/foil'
dry_run=false
while [ "$#" -gt 0 ]; do
  case "$1" in
    --runner-dir|--runner-name|--repo-url)
      [ "$#" -ge 2 ] && [ -n "$2" ] || fail 'option requires a value'
      case "$1" in
        --runner-dir) runner_dir="$2" ;;
        --runner-name) runner_name="$2" ;;
        --repo-url) repo_url="$2" ;;
      esac
      shift 2
      ;;
    --dry-run) dry_run=true; shift ;;
    --help) usage; exit 0 ;;
    *) usage >&2; fail 'unknown option' ;;
  esac
done

case "$runner_name" in foil-mm1|foil-mm2|foil-mm3) ;; *) fail 'invalid runner name' ;; esac
[ "$repo_url" = 'https://github.com/usefoil/foil' ] || fail 'repository URL must be https://github.com/usefoil/foil'
[ -n "$runner_dir" ] && [ -d "$runner_dir" ] || fail 'runner directory must already exist'
[ "$EUID" -ne 0 ] || fail 'run as the graphical test user, never root or sudo'
command -v node >/dev/null 2>&1 || fail 'Node.js is required to validate runner metadata'
cd "$runner_dir" || fail 'cannot enter runner directory'
[ -x ./config.sh ] || fail 'runner directory must contain executable config.sh'

validate_registration() {
  node -e '
    try {
      const fs = require("fs"), text = fs.readFileSync(".runner", "utf8").replace(/^\uFEFF/, ""), r = JSON.parse(text);
      process.exit(r.gitHubUrl === process.argv[1] && r.agentName === process.argv[2] ? 0 : 1);
    } catch { process.exit(1); }
  ' "$repo_url" "$runner_name" >/dev/null 2>&1
}

validate_marker() {
  node -e '
    try {
      const fs = require("fs"), m = JSON.parse(fs.readFileSync(".foil-runner-bootstrap.json", "utf8"));
      process.exit(m.schemaVersion === 1 && m.repoUrl === process.argv[1] &&
        m.runnerName === process.argv[2] && Array.isArray(m.labels) &&
        m.labels.length === 1 && m.labels[0] === "foil-deterministic" ? 0 : 1);
    } catch { process.exit(1); }
  ' "$repo_url" "$runner_name" >/dev/null 2>&1
}

verify_service() {
  [ -x ./svc.sh ] || fail 'missing executable svc.sh; maintenance repair required'
  local status_output
  # Upstream macOS svc.sh returns zero for Stopped/not installed, so inspect facts.
  status_output="$(./svc.sh status 2>/dev/null)" || fail 'service status command failed'
  if ! printf '%s\n' "$status_output" | node -e '
    const s = require("fs").readFileSync(0, "utf8"), expected = process.argv[1];
    const running = s.split(/\r?\n/).some(line => {
      const fields = line.trim().split(/\s+/);
      return fields.length === 3 && /^[1-9][0-9]*$/.test(fields[0]) && fields[2] === expected;
    });
    process.exit(/^Started:\s*$/m.test(s) && running ? 0 : 1);
  ' "actions.runner.usefoil-foil.$runner_name" >/dev/null 2>&1; then
    fail 'expected per-user service is not running; inspect svc.sh status during maintenance'
  fi
}

if [ -e .runner ] || [ -L .runner ]; then
  validate_registration || fail 'existing .runner is malformed or belongs to another repository/name; refusing replacement'
  if ! validate_marker; then
    if [ "$dry_run" = true ]; then
      printf '%s\n' 'dry-run: maintenance repair required: stop the old service, explicitly choose a fresh runner directory, then bootstrap there with --labels foil-deterministic'
      exit 0
    fi
    fail 'bootstrap marker missing/mismatched; maintenance repair requires stopping the old service and explicitly choosing a fresh runner directory'
  fi
  if [ "$dry_run" = true ]; then
    printf '%s\n' 'dry-run: local registration and marker match --labels foil-deterministic; would verify per-user svc.sh status'
    exit 0
  fi
  unset RUNNER_REGISTRATION_TOKEN
  verify_service
  printf '%s\n' 'Local registration, bootstrap marker, and running per-user service verified. Verify authoritative labels with the controller inventory before enabling the pool.'
  exit 0
fi

# Do not configure over partial credentials, a service, or a previous marker.
for state_file in .credentials .credentials_rsaparams .service .foil-runner-bootstrap.json; do
  if [ -e "$state_file" ] || [ -L "$state_file" ]; then
    fail 'unconfigured directory contains existing runner state; choose a fresh directory during maintenance'
  fi
done
if [ "$dry_run" = true ]; then
  printf '%s\n' "dry-run: ./config.sh --unattended --url https://github.com/usefoil/foil --name $runner_name --labels foil-deterministic --work _work --replace --token [REDACTED]"
  printf '%s\n' 'dry-run: validate .runner; write non-secret bootstrap marker; ./svc.sh install; ./svc.sh start; verify ./svc.sh status (per-user, without sudo)'
  exit 0
fi
[ -n "${RUNNER_REGISTRATION_TOKEN:-}" ] || fail 'RUNNER_REGISTRATION_TOKEN is required for a fresh registration'

# --replace handles a server-side duplicate name, never an existing local .runner.
# Discard child output: even a failed config/service command must not echo secrets.
./config.sh --unattended --url "$repo_url" --name "$runner_name" \
  --labels foil-deterministic --work _work --replace \
  --token "$RUNNER_REGISTRATION_TOKEN" >/dev/null 2>&1 || fail 'runner configuration failed; inspect protected runner diagnostics during maintenance'
unset RUNNER_REGISTRATION_TOKEN
validate_registration || fail 'configured .runner does not match the requested repository/name; service not started'
node -e '
  const fs = require("fs");
  fs.writeFileSync(".foil-runner-bootstrap.json", JSON.stringify({schemaVersion: 1,
    repoUrl: process.argv[1], runnerName: process.argv[2], labels: ["foil-deterministic"]}, null, 2) + "\n",
    {mode: 0o600, flag: "wx"});
' "$repo_url" "$runner_name" >/dev/null 2>&1 || fail 'cannot create bootstrap marker; service not started'
[ -x ./svc.sh ] || fail 'runner configuration did not produce executable svc.sh'
./svc.sh install >/dev/null 2>&1 || fail 'per-user service installation failed; inspect partial setup during maintenance'
./svc.sh start >/dev/null 2>&1 || fail 'per-user service start failed; inspect partial setup during maintenance'
verify_service
printf '%s\n' 'Runner configured and per-user service started. Verify authoritative labels with the controller inventory before enabling the pool.'
