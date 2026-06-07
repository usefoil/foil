# T999 Final Audit - Physical Harness

## Verdict

`full_outcome_complete: true`

The v0.18 oracle is satisfied.

## Requirement Audit

- Check whether the preview iPhone and WDA endpoint are reachable:
  - Proven by `notes/receipts/status.json`.
  - Device is present; WDA project and `iproxy` are present; WDA readiness is
    reported as a boolean instead of assumed.
- Start or print the exact WDA command needed for `iPhone-preview`:
  - Proven by `scripts/ios-physical-harness.py wda-command` verification and
    the runbook update.
  - Live WDA was also started with the same command family for session/fetch
    proof.
- Create a current-app WDA session without relaunching sensitive apps:
  - Proven by `notes/receipts/live-session.json`.
  - Receipt records `bundleIdProvided=false`.
- Stage a sterile fake transcript into the App Group at the correct path:
  - Proven by `notes/receipts/app-group-stage.json`.
  - Receipt records destination `Library/foil-keyboard-snapshot.json`,
    readback `phase=complete`, and `hasTranscript=true`.
- Read back only sanitized App Group state:
  - Proven by `notes/receipts/app-group-stage.json`,
    `notes/receipts/app-group-reset.json`, and
    `notes/receipts/self-test.json`.
  - Receipts contain hashes and lengths, not transcript bodies.
- Collect sanitized WDA receipts through the existing evidence helper:
  - Proven by `scripts/ios-physical-harness.py receipt` verification and
    `notes/receipts/self-test.json`.
  - The self-test proves a good fixture passes and a bad count fails.
- Reset the App Group to idle/no transcript after proof:
  - Proven by `notes/receipts/app-group-reset.json`.
  - Receipt records readback `phase=idle` and `hasTranscript=false`.

## Strongest Realistic Failure Mode

The harness could appear privacy-safe while committing raw host-app source,
Messages text, transcript bodies, or credentials into docs/receipts.

## Disproof Evidence

- `rg` scan for the physical sterile transcript phrase found no committed
  matches.
- `rg` scan for the receipt-wrapper fixture phrase found no committed matches.
- `rg` scan for the observed Messages collection/timestamp strings from WDA
  logs, raw XML element markers, and raw value-attribute markers in committed
  v0.18 docs found no raw WDA source. The only Messages bundle-id hit is the
  intentional privacy warning in `notes/T001-scout.md`.
- Secret scan over touched files found no App Store Connect key id, issuer id,
  Groq key variable, `sk-` token, AWS key, or private-key block.
- Live `fetch-source` wrote raw WDA source to a temporary `/tmp` directory,
  printed only sha/byte metadata, and the run deleted the temporary directory.
- `pgrep` check after cleanup found no running WDA/xcodebuild/devicectl
  diagnostic process.

## Verification Commands

- `python3 -m py_compile scripts/ios-physical-wda-evidence.py scripts/ios-physical-harness.py`
- `scripts/ios-physical-harness.py --help`
- `scripts/ios-physical-harness.py status`
- `scripts/ios-physical-harness.py wda-command`
- `scripts/ios-physical-harness.py self-test`
- `scripts/ios-physical-harness.py receipt ...`
- `scripts/ios-physical-harness.py stage-transcript --transcript-file ...`
- `scripts/ios-physical-harness.py reset-transcript`
- `scripts/ios-physical-harness.py session --wda-url http://192.168.1.40:8100`
- `scripts/ios-physical-harness.py fetch-source --wda-url http://192.168.1.40:8100 ...`
- `scripts/ios-physical-harness.py delete-session --wda-url http://192.168.1.40:8100 ...`
- `node /Users/neonwatty/.codex/plugins/cache/goalbuddy/goalbuddy/0.3.8/skills/goalbuddy/scripts/check-goal-state.mjs docs/goals/ios-v0.18-physical-harness/state.yaml`
- `git diff --check`
- targeted raw-content and secret scans

## Residual Risk

The harness proves it can safely fetch source to `/tmp`, but future target-app
boards still need to choose sterile screens and expectations before committing
any target-specific sanitized WDA receipts.
