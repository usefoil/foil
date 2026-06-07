# T003 Worker - Physical Harness

## Result

Done.

## Summary

Added `scripts/ios-physical-harness.py` as the repo-native wrapper for physical
iPhone checks. It provides sanitized status, WDA command/session helpers,
canonical App Group stage/reset/summary helpers, WDA source fetching to an
explicit file, a receipt wrapper around the existing evidence helper, and a
fixture-only self-test.

Updated `docs/ios-physical-automation-runbook.md` so future physical boards use
the harness as the preferred path while keeping the lower-level commands as
escape hatches.

## Changed Files

- `scripts/ios-physical-harness.py`
- `docs/ios-physical-automation-runbook.md`
- `docs/goals/ios-v0.18-physical-harness/notes/T003-worker.md`
- `docs/goals/ios-v0.18-physical-harness/notes/receipts/status.json`
- `docs/goals/ios-v0.18-physical-harness/notes/receipts/self-test.json`
- `docs/goals/ios-v0.18-physical-harness/notes/receipts/app-group-stage.json`
- `docs/goals/ios-v0.18-physical-harness/notes/receipts/app-group-reset.json`
- `docs/goals/ios-v0.18-physical-harness/notes/receipts/live-session.json`
- `docs/goals/ios-v0.18-physical-harness/notes/receipts/live-fetch-source.json`
- `docs/goals/ios-v0.18-physical-harness/notes/receipts/live-delete-session.json`
- `docs/goals/ios-v0.18-physical-harness/state.yaml`

## Evidence

- `python3 -m py_compile scripts/ios-physical-wda-evidence.py scripts/ios-physical-harness.py`
  passed.
- `scripts/ios-physical-harness.py --help` listed all required subcommands:
  `status`, `wda-command`, `session`, `delete-session`, `fetch-source`,
  `stage-transcript`, `reset-transcript`, `app-group-summary`, `receipt`, and
  `self-test`.
- `scripts/ios-physical-harness.py status` wrote
  `notes/receipts/status.json`, proving:
  - `iPhone-preview` is present and looks available.
  - WDA project is present.
  - `iproxy` is present.
  - WDA is currently down at `http://127.0.0.1:8100`, which the harness reports
    without failing status mode.
- `scripts/ios-physical-harness.py self-test` wrote
  `notes/receipts/self-test.json`, proving:
  - the evidence helper passes a good WDA fixture;
  - the evidence helper fails a bad count;
  - summaries omit the raw transcript;
  - complete summaries contain only transcript hash/length;
  - idle summaries contain no transcript hash.
- `scripts/ios-physical-harness.py stage-transcript` wrote
  `notes/receipts/app-group-stage.json`, proving the harness wrote to and read
  back `Library/foil-keyboard-snapshot.json` with `phase=complete` and
  `hasTranscript=true`.
- `scripts/ios-physical-harness.py reset-transcript` wrote
  `notes/receipts/app-group-reset.json`, proving the harness wrote to and read
  back the same canonical path with `phase=idle` and `hasTranscript=false`.
- After WDA started at `http://192.168.1.40:8100`,
  `scripts/ios-physical-harness.py session` wrote
  `notes/receipts/live-session.json`, proving a current-app session was created
  with `bundleIdProvided=false`.
- `scripts/ios-physical-harness.py fetch-source` wrote
  `notes/receipts/live-fetch-source.json`, proving the live WDA source path can
  write to an explicit `/tmp` file and report only sha/byte metadata with
  `printedRawSource=false`.
- `scripts/ios-physical-harness.py delete-session` wrote
  `notes/receipts/live-delete-session.json`, proving the live WDA session was
  deleted.

## Privacy Boundary

- The harness does not print raw WDA source; `fetch-source` writes only to an
  explicit caller-provided file path and prints sha/byte metadata.
- App Group write/readback receipts print transcript hash and length, not the
  transcript body.
- The current-app WDA `session` command deliberately omits `bundleId`, preserving
  the safe Messages flow discovered in v0.17.

## Residual Risk

The live `fetch-source` command necessarily wrote raw WDA source to a temporary
file under `/tmp`, then the run deleted that temporary directory. The committed
receipt contains only session id, output path, sha, byte count, and
`printedRawSource=false`; it does not include raw XML or host-app text.
