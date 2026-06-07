# T001 Scout - Physical Harness Map

## Result

Done. The proven physical path is ready to wrap in a small repo-native harness.
The current missing layer is orchestration, not another target-app proof.

## Current Proven Commands And Invariants

- Device readiness comes from `xcrun devicectl list devices`.
- The preview device identifier remains
  `5320F5AD-2A71-50AC-94FE-207B544B6247`.
- The WDA xcodebuild destination used by earlier receipts remains
  `00008030-001A0C980A33C02E`.
- The Appium-bundled WDA project is present at
  `/Users/neonwatty/.appium/node_modules/appium-xcuitest-driver/node_modules/appium-webdriveragent/WebDriverAgent.xcodeproj`.
- `iproxy` is installed at `/opt/homebrew/bin/iproxy`.
- Current live state during Scout:
  - `iPhone-preview` is `available (paired)`.
  - `http://127.0.0.1:8100/status` is not reachable, so WDA is currently down.

## Existing Evidence Helper

`scripts/ios-physical-wda-evidence.py` already provides the core privacy gate:

- parses WDA `/source` JSON or raw XML;
- checks required/forbidden accessibility identifiers;
- checks identifier attributes such as
  `foil-keyboard-insert-latest.enabled=false`;
- hashes expected private text instead of writing it to receipts;
- summarizes App Group snapshots as phase, hasTranscript, and transcript hash;
- exits non-zero when an expectation fails.

Prior receipts from v0.15-v0.17 show this helper is already useful for:

- Safari textarea pre/post insertion;
- Safari secure-field custom-keyboard rejection;
- Reminders pre/post/cleanup;
- sterile Messages pre/post/cleanup.

## Harness Command Proposal

Add `scripts/ios-physical-harness.py` with subcommands:

- `status`: report sanitized device, WDA, WDA project, and `iproxy` readiness.
- `wda-command`: print the exact WDA xcodebuild command for
  `iPhone-preview`.
- `session`: create a current-app WDA session without a `bundleId`, so sensitive
  apps are not relaunched into private list surfaces.
- `delete-session`: delete a WDA session id.
- `fetch-source`: fetch WDA `/source` for a caller-provided session id to a
  caller-provided local path; keep it out of committed receipts.
- `stage-transcript`: write a sterile transcript snapshot to the App Group at
  `Library/foil-keyboard-snapshot.json` and read it back as a sanitized
  summary.
- `reset-transcript`: write idle/no transcript state to the same canonical App
  Group path and read it back as a sanitized summary.
- `app-group-summary`: copy the canonical snapshot from the device and print
  only phase, hasTranscript, message hash, transcript hash, and file hash.
- `receipt`: wrap `ios-physical-wda-evidence.py` for sanitized receipt
  generation while preserving its non-zero expectation behavior.
- `self-test`: run fixture-only tests that prove summaries hash text and that
  failing WDA expectations fail closed.

## Privacy And Cleanup Requirements

- Never create a WDA session with `bundleId=com.apple.MobileSMS` for Messages;
  use current-app sessions after the operator focuses a sterile thread.
- Never print transcript bodies from App Group summaries.
- Never print raw WDA XML from `fetch-source`; write to an explicit local file.
- Default receipt paths should live outside committed notes unless the caller
  deliberately copies sanitized JSON into `docs/goals/.../notes/receipts`.
- `reset-transcript` must write `phase=idle` and `transcript=null` to the same
  canonical path used by `stage-transcript`.
- The script should be useful when WDA is down: `status`, `wda-command`, and
  `self-test` should still work.

## Fixture/Self-Test Strategy

Use temporary files under `/tmp` to avoid shipping private fixtures. Self-test
should:

- create a tiny WDA source fixture with Foil identifiers and one sterile value;
- run the existing evidence helper with a passing expectation;
- run the helper with an intentionally wrong count and verify it fails;
- create complete and idle App Group snapshot fixtures and verify summaries do
  not include the raw transcript text.

## Candidate Worker Slice

Objective: implement the harness subcommands, update the physical automation
runbook, add fixture self-test coverage, and run a physical-safe status proof.

Allowed files:

- `scripts/ios-physical-harness.py`
- `scripts/ios-physical-wda-evidence.py` only if needed for import-safe reuse
  or a narrow bug fix
- `docs/ios-physical-automation-runbook.md`
- `docs/goals/ios-v0.18-physical-harness/**`

Verification:

- `python3 -m py_compile scripts/ios-physical-wda-evidence.py`
- `python3 -m py_compile scripts/ios-physical-harness.py`
- `scripts/ios-physical-harness.py --help`
- `scripts/ios-physical-harness.py status`
- `scripts/ios-physical-harness.py wda-command`
- `scripts/ios-physical-harness.py self-test`
- `node .../check-goal-state.mjs docs/goals/ios-v0.18-physical-harness/state.yaml`
- `git diff --check`
- targeted raw-content and secret scan over touched files

Stop if:

- physical commands require unlock/install/operator action;
- a command would print credentials or private host-app content;
- implementation needs product behavior changes outside the harness scope.
