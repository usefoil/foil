# iOS Physical Automation Runbook

This runbook captures the current Foil iOS physical-device automation path for
future GoalBuddy/Codex runs. It is for safe, repeatable readiness checks and
privacy-preserving physical proof on `iPhone-preview`.

## Privacy Boundaries

- Do not commit raw WDA accessibility trees from Messages, Reminders, Safari, or any app that may expose private content.
- Do not commit screenshots unless the target context is sterile and intentionally created for evidence.
- Do not print or commit API keys, transcript bodies, phone numbers, contacts, reminder titles, message text, or private URLs.
- Prefer boolean/hash evidence for host apps: keyboard visible, insert button enabled, target value changed, App Group state reset.
- Messages remains out of scope until a dedicated safe self/test thread exists.

## Device Readiness

List paired/connected devices:

```bash
xcrun devicectl list devices
```

Expected useful state:

- `iPhone-preview` is `connected`.
- Device identifier is currently `5320F5AD-2A71-50AC-94FE-207B544B6247`.
- xcodebuild destination id used by WDA has been `00008030-001A0C980A33C02E`.

If the device is unavailable, locked, or preparation fails, stop the run and
record the exact `devicectl` output.

## Tooling Checks

Check the local WebDriverAgent project:

```bash
test -d /Users/neonwatty/.appium/node_modules/appium-xcuitest-driver/node_modules/appium-webdriveragent/WebDriverAgent.xcodeproj
```

Check for `iproxy`:

```bash
command -v iproxy
```

Xcode's Python does not currently include `pymobiledevice3`; do not assume it is
available:

```bash
/Applications/Xcode.app/Contents/Developer/usr/bin/python3 -m pymobiledevice3 --help
```

## WDA Readiness

First check whether WDA is already reachable:

```bash
curl -sS --max-time 2 http://127.0.0.1:8100/status
```

A failed connection means WDA is down or not forwarded. That is a normal starting
state between physical test runs.

The preferred repo-native readiness check is:

```bash
scripts/ios-physical-harness.py status
```

It prints sanitized JSON for device visibility, WDA reachability, WDA project
presence, and `iproxy` presence. It hashes the raw device line instead of
printing the full `devicectl` row.

## Start WDA

Use the Appium-bundled WebDriverAgent project and keep this command running
while physical UI automation is needed:

```bash
xcodebuild \
  -project /Users/neonwatty/.appium/node_modules/appium-xcuitest-driver/node_modules/appium-webdriveragent/WebDriverAgent.xcodeproj \
  -scheme WebDriverAgentRunner-nodebug \
  -destination 'id=00008030-001A0C980A33C02E' \
  -configuration Debug \
  DEVELOPMENT_TEAM=B3A6AN2HA4 \
  CODE_SIGN_STYLE=Automatic \
  PRODUCT_BUNDLE_IDENTIFIER=com.neonwatty.WebDriverAgentRunner \
  -allowProvisioningUpdates \
  test 2>&1 | tee /tmp/foil-ios-wda.log
```

To print this command from the harness:

```bash
scripts/ios-physical-harness.py wda-command
```

Then poll:

```bash
curl -sS --max-time 2 http://127.0.0.1:8100/status
```

If WDA reports ready, later WDA HTTP calls can use `http://127.0.0.1:8100`.
Older receipts also used `http://192.168.1.40:8100`; prefer localhost when a
tunnel/forward is active.

## Cleanup

Before handing off or ending a run, stop WDA and any sterile local test server:

```bash
pgrep -af 'WebDriverAgent.xcodeproj.*WebDriverAgentRunner-nodebug|xcodebuild.*WebDriverAgent|secure-field-test-server|8945' || true
```

Terminate only matching automation processes that this run started:

```bash
kill <pid>
```

Verify they are gone:

```bash
pgrep -af 'WebDriverAgent.xcodeproj.*WebDriverAgentRunner-nodebug|xcodebuild.*WebDriverAgent|secure-field-test-server|8945' || true
```

## Foil App Install Pattern

After building a physical-device `.app`, install it with:

```bash
xcrun devicectl device install app \
  --device 5320F5AD-2A71-50AC-94FE-207B544B6247 \
  '<path-to-built>/Foil iOS.app'
```

Record the command and the installed app path in the GoalBuddy receipt.

## App Group State Proof

Copy the canonical keyboard snapshot after insert/reset checks:

```bash
xcrun devicectl device copy from \
  --device 5320F5AD-2A71-50AC-94FE-207B544B6247 \
  --domain-type appGroupDataContainer \
  --domain-identifier group.com.neonwatty.FoilIOS \
  --source Library/foil-keyboard-snapshot.json \
  --destination /tmp/foil-keyboard-snapshot.json
```

Receipts should record sanitized state such as phase, message category,
`hasTranscript`, and whether the keyboard returned to idle/no transcript. Avoid
recording transcript bodies.

The preferred harness commands are:

```bash
scripts/ios-physical-harness.py stage-transcript \
  --transcript-file /tmp/sterile-transcript.txt

scripts/ios-physical-harness.py app-group-summary

scripts/ios-physical-harness.py reset-transcript
```

`stage-transcript` and `reset-transcript` both write to the canonical
`Library/foil-keyboard-snapshot.json` path, copy that snapshot back, and print
only sanitized summaries: phase, hasTranscript, message hash, transcript hash,
transcript length, file hash, and copy result metadata.

## Sanitized WDA Evidence Helper

After a target-app probe, save WDA source to a local artifact path and convert it
to a sanitized receipt. The helper reports source hashes, accessibility
identifier presence, private-text hashes, and value-attribute counts without
printing transcript or host-app text.

```bash
curl -sS http://127.0.0.1:8100/session/$WDA_SESSION_ID/source \
  > /tmp/foil-ios-notes-after-insert.json

scripts/ios-physical-wda-evidence.py \
  --source /tmp/foil-ios-notes-after-insert.json \
  --target notes \
  --expect-value-count "$STERILE_PHRASE=1" \
  --require-identifier foil-keyboard-root \
  --expect-identifier-state foil-keyboard-insert-latest.enabled=false \
  --write-json /tmp/foil-ios-notes-after-insert-receipt.json
```

Use `--require-identifier foil-keyboard-insert-latest` before insertion when the
row needs to prove Insert latest is available, and
`--expect-identifier-state foil-keyboard-insert-latest.enabled=false` after
insertion to prove the button is no longer actionable. Use
`--forbid-identifier foil-keyboard-root` for secure-field rejection rows where
iOS should replace custom keyboards with the native secure keyboard, plus
`--require-text "secure length: 0"` and `--forbid-text "secure length: 19"` when
using the sterile Safari fixture. The command exits non-zero when any
expectation fails, so future GoalBuddy boards can treat the receipt as a real
gate instead of a narrative note.

The harness can create the current-app WDA session and fetch source without
printing raw XML:

```bash
scripts/ios-physical-harness.py session

scripts/ios-physical-harness.py fetch-source "$WDA_SESSION_ID" \
  --output /tmp/foil-ios-target-source.json
```

For sensitive apps, especially Messages, use `session` only after the operator
has already focused a sterile field. Do not create a WDA session with a Messages
`bundleId`; that can relaunch Messages into a private list/search surface.

The harness can also wrap the evidence helper:

```bash
scripts/ios-physical-harness.py receipt \
  --source /tmp/foil-ios-target-source.json \
  --target notes \
  --expect-value-count "$STERILE_PHRASE=1" \
  --require-identifier foil-keyboard-root \
  --expect-identifier-state foil-keyboard-insert-latest.enabled=false \
  --write-json /tmp/foil-ios-target-receipt.json
```

The wrapper preserves the evidence helper's fail-closed exit status.

Fixture-only confidence check:

```bash
scripts/ios-physical-harness.py self-test
```

The self-test proves a good WDA fixture passes, a bad count fails, and App Group
summaries omit raw transcript text.

## Safe Target-App Evidence

Use sterile contexts only:

- Notes: create a fresh note and record hash/boolean insertion proof.
- Safari: use a blank/search field or a sterile local fixture.
- Reminders: create a new safe reminder row and record sanitized proof only.
- Secure fields: use a sterile password-field fixture and prove the custom keyboard is absent.
- Messages: skip unless the operator provides a dedicated safe self/test thread.

For target apps, record the smallest proof that rules out the failure:

- Foil keyboard visible or absent as expected.
- Insert latest enabled/disabled as expected.
- Target field changed when insertion should occur.
- Target field did not change when insertion should be blocked.
- App Group state returned to ready/no transcript after insertion.

## Receipt Checklist

Every physical automation receipt should include:

- branch and app build/install command;
- device identifier and device readiness output;
- WDA status before and after startup;
- exact WDA command or exact blocker;
- sanitized target-app proof;
- App Group state after insertion/reset;
- cleanup command and confirmation;
- `git diff --check` and secret/private-string scan results.
