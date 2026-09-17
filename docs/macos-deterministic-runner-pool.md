# Deterministic Mac runner pool operations

This runbook prepares three interchangeable, repository-scoped runners for
`usefoil/foil`. The workflow remains **shadow/non-required** until host evidence,
coverage, timing, and the unavailable-runner behavior have been accepted.

## Authorization and host inventory

Runner registration/replacement, service changes, reboots, OS/Xcode upgrades,
cleanup, and branch-protection changes require an **explicitly authorized
maintenance window**. Record its owner, hosts, exact directories, affected runner
names, approved operations, downtime, and rollback decision before mutation.
This document and the local tests do not authorize host maintenance. Never run
bootstrap automatically from a CI job.

| SSH alias | Intended GitHub runner name | Scheduling labels |
| --- | --- | --- |
| `mm1` | `foil-mm1` | `self-hosted`, `macOS`, `ARM64`, `foil-deterministic` |
| `mm2` | `foil-mm2` | same shared labels |
| `mm3` | `foil-mm3` | same shared labels |

Use `ssh mm1`, `ssh mm2`, or `ssh mm3` from the controller. Confirm the alias's
hostname and account with `hostname` and `id` before changes. Historical names
(`mac-mini-1`, `foil-mac-mini-2`) are inventory clues, not proof of current state.
Audit `mm2` and `mm3` for unrelated organization/repository runners in particular.
Do not repurpose their directories or remove their registrations or credentials.

Record the Foil checkout, fresh runner directory, previous runner directories,
and graphical test account separately for each host. There are no assumed
absolute installation paths. All `<...>` values below are operator placeholders:
replace them with paths/labels/IDs verified in that maintenance record before
execution. `FOIL_CHECKOUT`, `FOIL_RUNNER_DIR`, `FOIL_RUNNER_NAME`,
`UNRELATED_RUNNER_DIR`, and `UNRELATED_SERVICE_LABEL` are operator shell variables,
not persistent configuration. Keep the dedicated test account non-admin with an
active graphical login; the allowed console user is `foilci`. An SSH shell
alone does not establish the graphical session.

## Pinned toolchain and prerequisites

The checked-in authority is `scripts/ci/runner-baseline.json`:

| Fact | Required value |
| --- | --- |
| Architecture | `arm64` |
| macOS product/build | `27.0` / `26A428` |
| Xcode version/build | `27.0` / `27A266a` |
| Free space | at least `30000000000` bytes |

On **each** host, inspect before any upgrade or registration:

```bash
sw_vers
uname -m
xcodebuild -version
xcode-select -p
stat -f '%Su' /dev/console
ioreg -n Root -d1 -a | plutil -extract IOConsoleLocked raw -o - -
DevToolsSecurity -status
df -kP "$FOIL_RUNNER_DIR"
launchctl list
```

Manually install the pinned macOS/Xcode versions and Xcode components only within
the approved window; do not use floating `latest` upgrades. Confirm the exact
version **and build** on all three hosts afterward. If selection needs repair,
the authorized administrator selects the audited installation:

```bash
sudo xcode-select --switch '<verified-Xcode.app>/Contents/Developer'
```

Check `DEVELOPER_DIR` in the runner environment because it can override selection.
Arrange an awake, unlocked graphical session and display, disable automatic
screen locking plus automatic OS/Xcode updates through managed settings, and
verify Developer Mode before availability. The preflight rejects a locked
console because a per-user runner can remain online while XCUITest is unable to
foreground the app.
Use the repository's existing signing setup; do not reset Keychain or TCC data.

When the accepted Xcode is installed outside the globally selected path, pin it
for the dedicated runner before bootstrap by writing only the audited developer
directory to the official runner's `.env` file. Also invoke bootstrap with a
`PATH` that includes the required Node.js binary; the runner installer captures
that path in `.path` for its per-user service. For example:

```bash
printf '%s\n' "DEVELOPER_DIR=$VERIFIED_XCODE_APP/Contents/Developer" \
  >"$FOIL_RUNNER_DIR/.env"
PATH="$FOIL_NODE_BIN_DIR:/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  bash "$FOIL_CHECKOUT/scripts/ci/bootstrap-foil-runner.sh" \
  --runner-dir "$FOIL_RUNNER_DIR" --runner-name "$FOIL_RUNNER_NAME" --dry-run
```

Require `xcodebuild -version` with that same `DEVELOPER_DIR` to match the pinned
version/build. Do not place credentials in `.env` or `.path`. The live workflow
preflight records the toolchain actually inherited by the runner service.

Provision an official macOS ARM64 Actions runner release in the selected **fresh**
directory, verifying its release checksum using the
[GitHub runner release instructions](https://github.com/actions/runner/releases).
This bootstrap does not download a runner, install prerequisites, select Xcode,
or create a graphical login. It requires Bash 3.2+, Node.js, and executable
`config.sh`; configuration must produce executable `svc.sh`. Node.js is also
required by the shard executor. The controller needs authenticated `gh` with
permission to inspect/manage `usefoil/foil` runners; the bootstrap itself has no
`gh` or GitHub-authentication dependency beyond the temporary registration token.

## Reversibly stop conflicting services

First drain running jobs and confirm the affected runner is idle in GitHub's
inventory. Use the graphical test account, without sudo. Inspect each approved
runner directory's `.runner` for `agentName` and `gitHubUrl`, and use its own
service script. Do not print `.credentials` or credential parameters.

```bash
cd "$UNRELATED_RUNNER_DIR"
./svc.sh status
./svc.sh stop
./svc.sh status
launchctl list
```

For unrelated runners on `mm2`/`mm3`, record their directories and exact service
labels and retain `.runner`, `.credentials*`, `.service`, and LaunchAgent files.
`svc.sh stop` unloads the service reversibly; it is not deletion. A stopped
LaunchAgent can return after login/reboot. Where the approved window includes
keeping it disabled across reboot, disable only its inventoried user-domain label:

```bash
launchctl disable "gui/$(id -u)/$UNRELATED_SERVICE_LABEL"
```

Rollback uses `launchctl enable` for that same label and the original directory's
`svc.sh start`. Do not disable a wildcard or a system domain. Apply the same
drain/stop discipline to an old Foil service before replacing its server name.
The desired preflight state is exactly one loaded Actions service in the test
account: `actions.runner.usefoil-foil.<foil-mmN>`.

## Dry-run and registration

Set the verified checkout and directory variables for the current host; use the
table's exact runner name. Run from the graphical test user's environment:

```bash
bash "$FOIL_CHECKOUT/scripts/ci/bootstrap-foil-runner.sh" \
  --runner-dir "$FOIL_RUNNER_DIR" --runner-name "$FOIL_RUNNER_NAME" --dry-run
```

Dry-run validates local metadata and reports planned commands; it calls neither
`config.sh` nor `svc.sh`, creates no files, and needs no token. It is **not** proof
of service health, server labels, GUI state, or a working toolchain.

For the approved real registration, obtain a fresh, short-lived registration
token with the following command in a trusted, unrecorded shell authenticated to
GitHub (or securely pass the result to the host's unrecorded shell). Avoid shell
tracing, terminal recording, clipboard logs, chat, command-line token literals,
and shared environment dumps. A registration token is not a persistent PAT.

```bash
set +x
RUNNER_REGISTRATION_TOKEN="$(gh api -X POST repos/usefoil/foil/actions/runners/registration-token --jq .token)"
export RUNNER_REGISTRATION_TOKEN
if bash "$FOIL_CHECKOUT/scripts/ci/bootstrap-foil-runner.sh" \
  --runner-dir "$FOIL_RUNNER_DIR" --runner-name "$FOIL_RUNNER_NAME"; then
  unset RUNNER_REGISTRATION_TOKEN
else
  unset RUNNER_REGISTRATION_TOKEN
  printf '%s\n' 'Bootstrap failed; inspect the recorded maintenance state before retrying.'
fi
```

If `gh` is only on the controller, run token creation there and use an approved
secret-transfer channel into the host environment; do not put the token in SSH
arguments. Unset it on both machines afterward. The script suppresses child
stdout/stderr and disables inherited tracing. The runner CLI receives its token
as an argument internally, so do not collect process argument dumps during
registration. Treat runner diagnostic logs as sensitive and inspect them locally.

Fresh bootstrap validates the new `.runner`, writes the non-secret
`.foil-runner-bootstrap.json` marker, and runs `./svc.sh install`, `./svc.sh start`,
then `./svc.sh status` as the current user. These are per-user LaunchAgent
operations. Never invoke bootstrap or these service commands with sudo.

An existing directory succeeds without a token only when exact `gitHubUrl` and
`agentName`, marker schema/repository/name/`foil-deterministic` label, and running
service identity all match. The marker records bootstrap intent; it cannot prove
that someone has not changed labels on GitHub. The implementation accounts for
macOS `svc.sh status` returning zero when stopped by checking its running-state
output and PID. See upstream [runner settings](https://github.com/actions/runner/blob/main/src/Runner.Common/ConfigurationStore.cs)
and [macOS service implementation](https://github.com/actions/runner/blob/main/src/Misc/layoutbin/darwin.svc.sh.template).

### Existing or partial registration repair

Foreign/malformed `.runner` or another runner name fails closed, including in
dry-run. A matching `.runner` with a missing/mismatched marker fails closed in
normal mode; dry-run reports maintenance repair. Stop the old service and
explicitly choose a fresh directory during the approved window. Bootstrap that
directory with a fresh registration token. Never fabricate a marker to bypass
this check.

`--replace` replaces a **server-side duplicate runner name** from an unconfigured
local directory. It does not reconfigure a directory that already contains
`.runner`. The bootstrap never calls `config.sh remove`, deletes/moves credentials,
or overwrites an existing marker. Retain the old directory for diagnosis; a
server-side replacement may invalidate its credentials, so it is not a working
rollback registration merely because its files remain.

After a partial failure, inspect the exact directory and protected diagnostics.
If local registration and marker are valid, repair only the failed service step
within the window: `./svc.sh install` only if not installed, then `./svc.sh start`
only if stopped. Re-run bootstrap to verify. A missing marker or mismatched
registration requires the fresh-directory procedure. Do not loop registration
blindly or install repeatedly over an existing LaunchAgent.

## Authoritative inventory and read-only preflight

From the controller, query every page:

```bash
gh api --paginate repos/usefoil/foil/actions/runners \
  --jq '.runners[] | {id, name, os, status, busy, labels: [.labels[].name]}'
```

Before enabling the pool, require exactly one entry for each of `foil-mm1`,
`foil-mm2`, `foil-mm3`, all `online`, idle at handoff, macOS, and carrying
`self-hosted`, `macOS`, `ARM64`, and `foil-deterministic`. Match each returned ID
to its host's `.runner` `agentId`. Resolve duplicate/stale entries in a separately
approved operation; bootstrap does not delete them. Missing/incorrect labels or
inventory access failure blocks rollout even if local bootstrap passed.

From the Foil checkout on each host, exercise the preflight comparator with the
checked-in fixture first. This is a local dry-run of validation, **not host proof**:

```bash
cd "$FOIL_CHECKOUT"
PREFLIGHT_RECEIPTS="$(mktemp -d "${TMPDIR:-/tmp}/foil-preflight.XXXXXX")"
node scripts/ci/runner-preflight.mjs \
  --baseline scripts/ci/runner-baseline.json \
  --facts scripts/ci/tests/fixtures/healthy-runner.json \
  --output "$PREFLIGHT_RECEIPTS/fixture.json"
```

Then collect actual host facts (read-only apart from the receipt):

```bash
RUNNER_NAME="$FOIL_RUNNER_NAME" RUNNER_OS=macOS RUNNER_ARCH=ARM64 \
  node scripts/ci/runner-preflight.mjs \
  --baseline scripts/ci/runner-baseline.json \
  --output "$PREFLIGHT_RECEIPTS/host.json"
```

Require exit zero and `status: healthy`. Retain receipts with the maintenance
record. Run from the intended runner checkout/filesystem and graphical user so
disk and service facts are meaningful. The current preflight checks baseline,
free disk, console user, Developer Mode, and exactly one expected loaded runner
service. It does not replace server-label inventory, a UI smoke run, or proof of
permissions/signing. Unexpected services must be stopped through their approved
directory and the preflight repeated.

## Reboot proof and shadow gate acceptance

Within the approved window, reboot one host at a time with the site's normal
authorized procedure, log into its graphical test account, and establish the
awake display/session. A per-user LaunchAgent starts after user login; reboot
alone does not guarantee a usable runner. Confirm unrelated runners stay disabled
and retain post-reboot `launchctl list`, local bootstrap verification, actual-host
preflight receipt, and controller inventory for every host. Require the expected
service with a live PID and the corresponding GitHub runner online.

After all three pass, dispatch an authorized shadow run from the controller:

```bash
gh workflow run macos-deterministic-ui-gate.yml --repo usefoil/foil --ref '<reviewed-branch-or-tag>'
gh run list --repo usefoil/foil --workflow macos-deterministic-ui-gate.yml --limit 5
gh run view '<verified-run-id>' --repo usefoil/foil
```

Record the run's actual commit SHA and all three runner assignments. Retain
`deterministic-receipt-a/b/c`, `deterministic-shard-a/b/c`, and
`deterministic-gate-summary` artifacts. Verify complete manifest coverage, no
unexpected skips, repeated same-SHA consistency, post-reboot UI execution, and
representative timings before requiring `Foil Deterministic UI Gate` in branch
protection. Consult `scripts/ci/ui-test-shards.json` and the
acceptance checks in this runbook for coverage and rollout evidence. Branch
protection remains a separate explicitly authorized change.

**Accepted Task 7 limitation:** the read-only start watchdog turns the workflow
red after a missed **180-second** shard-start deadline, but cannot cancel queued
shards. The aggregate depends on those shard jobs and may keep waiting; a red
watchdog is not a completed aggregate check. Fifteen-minute shard execution
timeouts do not bound time spent queued or whole-workflow elapsed time. During
shadow rollout, deliberately assess unavailable-runner behavior in an approved
test window: record watchdog timing, queued shard state, aggregate completion
delay, and operator recovery. Resolve/accept this evidence before enforcement;
do not advertise a fifteen-minute end-to-end guarantee from the current workflow.
Any manual run cancellation requires operator authorization.

## Bounded disk cleanup

Drain the host and retain uploaded diagnostics before cleanup. Inspect disk use
with `df -kP` and `du -sh` on explicitly inventoried Foil paths. Never recursively
delete home, a runner installation, `_work`, a checkout, Keychain, TCC databases,
or shared DerivedData. Do not wildcard-delete old runs.

Choose one completed shard's actual `RUNNER_WORKSPACE` and exact run directory
`<workspace>/foil-ci-runs/<run-id>-<attempt>-<a|b|c>` from its evidence. The cleanup
script validates strict ancestry and the numeric run/attempt/shard basename.
Its `after` mode deletes the **entire selected run directory**, including any
evidence inside it, and refuses while scoped Foil processes remain. Preserve
needed artifacts elsewhere first. `before` can terminate scoped Foil processes,
so do not run it against an active job. Preview first:

```bash
FOIL_CI_DRY_RUN=1 bash "$FOIL_CHECKOUT/scripts/ci/runner-cleanup.sh" \
  --workspace-root '<verified-workspace>' --run-root '<verified-completed-run-directory>' --mode after
```

After inspecting the preview and confirming authorization, repeat that exact
command with `FOIL_CI_DRY_RUN=0`. No file deletion is reversible; preserve required
artifacts first. Bound any additional retention policy by verified paths, age,
and a byte budget agreed in the maintenance record. If disk remains below the
baseline, keep the runner unavailable and investigate instead of broad deletion.

## Rollback and toolchain upgrades

Stop dispatching shadow work, drain jobs, and stop the Foil service in its exact
directory with `./svc.sh stop`. Retain its files and diagnostics. For each
previous unrelated service, restore only the state changed in this window:

```bash
launchctl enable "gui/$(id -u)/$UNRELATED_SERVICE_LABEL"
cd "$UNRELATED_RUNNER_DIR"
./svc.sh start
./svc.sh status
```

Skip `enable` when no persistent disable was applied. Confirm its original
repository's inventory and active service state, and record the Foil pool as
unavailable. Do not simultaneously restart an old Foil runner whose server name
was replaced. Restoring that registration requires a new approved bootstrap in
a fresh directory and a fresh token; retained credentials may no longer work.
An already-required gate needs an explicitly approved branch-protection rollback
before service downtime; do not silently change required checks.

Plan OS/Xcode upgrades across all three hosts together. Drain the pool, preserve
pre-upgrade version/receipt evidence and an OS recovery plan, upgrade manually,
select Xcode, and rerun inventory, actual preflight, reboot proof, and repeated
shadow gates. Update the baseline manifest through review only with accepted
pool evidence; never relax checks on a single drifting host. If the approved
baseline changes, validation against the old manifest will intentionally fail
until the reviewed update is available. Roll back Xcode selection to a retained
verified installation if appropriate; OS rollback requires the prearranged
recovery procedure and authorization, not an assumed downgrade command.

## Repository-local verification

These tests use only temporary fake runner directories and stub runner commands:

```bash
bash scripts/ci/tests/test-bootstrap-foil-runner.sh
/bin/bash -n scripts/ci/bootstrap-foil-runner.sh scripts/ci/tests/test-bootstrap-foil-runner.sh
shellcheck scripts/ci/bootstrap-foil-runner.sh scripts/ci/tests/test-bootstrap-foil-runner.sh
git diff --check
rg -n 'mm1|mm2|mm3|foil-deterministic|rollback|reboot' docs/macos-deterministic-runner-pool.md
```

ShellCheck is optional if unavailable. `ssh`, `hostname`, `id`, `sw_vers`, `uname`,
`xcodebuild`, `xcode-select`, `stat`, `DevToolsSecurity`, `df`, `du`, `launchctl`,
`sudo`, `bash`, `node`, `gh`, `mktemp`, `git`, `rg`, and `shellcheck` are external
system/developer commands; `cd`, `set`, `export`, `unset`, and `printf` are shell
builtins. `config.sh`/`svc.sh` and runner state files belong to the separately
provisioned official runner installation. Other repository paths above are
checked in. Nothing in this local test proves actual host provisioning or
server availability; the maintenance owner must collect that evidence.
