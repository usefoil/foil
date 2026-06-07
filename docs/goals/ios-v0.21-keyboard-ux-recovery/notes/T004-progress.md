# T004 Progress

Status: partial. Physical app/install and App Group fixture proof advanced, but the keyboard UI receipt remains blocked by WDA automation mode.

## What Passed

- Built the current `codex/ios-v0.21-keyboard-ux-recovery` branch for `iPhone-preview`.
- Installed the resulting Debug app bundle on `iPhone-preview`.
- Confirmed the installed Foil iOS app reports version `0.1.0`, build `10`.
- Confirmed the canonical App Group snapshot began at `idle` with no transcript.
- Staged a sterile complete transcript fixture through the existing harness and read it back as `phase=complete`, `hasTranscript=true`, transcript length `36`, transcript hash only.
- Staged a stale non-complete fixture manually through the same `devicectl` App Group path and read it back as `phase=processing`, `hasTranscript=true`, transcript length `33`, transcript hash only.
- Reset the App Group to `idle` with no transcript after the stale fixture attempt.

No raw transcript, WDA source, screenshot, private host-app content, or credential was committed.

## WDA Blocker

The exact WDA command from the runbook was retried:

`xcodebuild -project /Users/neonwatty/.appium/node_modules/appium-xcuitest-driver/node_modules/appium-webdriveragent/WebDriverAgent.xcodeproj -scheme WebDriverAgentRunner-nodebug -destination 'id=00008030-001A0C980A33C02E' -configuration Debug DEVELOPMENT_TEAM=B3A6AN2HA4 CODE_SIGN_STYLE=Automatic PRODUCT_BUNDLE_IDENTIFIER=com.neonwatty.WebDriverAgentRunner -allowProvisioningUpdates test`

Observed result:

- The runner launched and printed `Running tests...`.
- Neither `http://192.168.1.40:8100/status` nor `http://127.0.0.1:8100/status` became reachable.
- After about one minute, the runner emitted `Timed out while enabling automation mode.`
- The command then prompted for `Password:`.
- No password was entered; the process was stopped.
- `pymobiledevice3 developer wda status` through both the user-local and
  `/opt/prcard` installs failed with `Failed to connect to service port`, so the
  alternate WDA control wrapper is also blocked until WDA service startup works.

Device facts at the time:

- `iPhone-preview` was available/paired.
- `passcodeRequired=false`.
- `unlockedSinceBoot=true`.
- Developer Mode was enabled.
- CoreDevice tunnel state was connected.

## Remaining Proof

T004 still needs WDA or an equivalent safe UI automation channel to prove:

- A stale non-complete snapshot with leftover transcript does not enable or expose actionable `Insert latest` in the physical keyboard UI.
- A complete snapshot enables `Insert latest`, inserts exactly once into a sterile target, and returns the App Group snapshot to `idle`/no transcript.
