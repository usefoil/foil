# T003 Worker

Result: local slice done; physical receipt blocked by WDA automation-mode startup.

## Summary

Implemented the approved insertability hardening:

- Added one shared `FoilKeyboardSnapshot.insertableTranscript` rule.
- `consumeTranscriptForInsertion()` now returns text only for `complete` snapshots with non-empty trimmed transcript, then clears shared state.
- `KeyboardViewController.refreshState()` now enables and colors `Insert latest` only when `insertableTranscript` exists.
- Reset/recovery remains available for non-idle or leftover transcript states.

## Evidence

- Focused simulator test command:

  `xcodebuild test -project FoiliOS/FoilIOS.xcodeproj -scheme FoilIOS -destination 'id=3078C4C7-E3E0-448A-B6AB-8AFE7A39F440' -only-testing:FoilIOSTests/FoilKeyboardBridgeTests -only-testing:FoilIOSTests/FoilDictationLoopPresentationTests`

  Result: passed. Xcode reported 17 selected tests, 0 failures.

- New bridge proof:

  `testConsumeTranscriptForInsertionIgnoresNonCompleteLeftoverTranscripts` stages leftover transcript text for `idle`, `handoffRequested`, `listening`, `processing`, and `failed`; every case returns `nil`, clears to `idle`, and records an `insert` storage operation.

- New shared-rule proof:

  `testInsertableTranscriptRequiresCompleteNonEmptyTranscript` proves complete non-empty text trims and inserts, complete blank text is rejected, and failed leftover text is rejected.

- New presentation proof:

  `testKeyboardNonCompleteLeftoverTranscriptDoesNotAdvertiseInsertLatest` proves leftover transcript text in non-complete phases does not present `Insert latest` or ready status copy.

- GoalBuddy checker:

  `node /Users/neonwatty/.codex/plugins/cache/goalbuddy/goalbuddy/0.3.8/skills/goalbuddy/scripts/check-goal-state.mjs docs/goals/ios-v0.21-keyboard-ux-recovery/state.yaml`

  Result before this receipt: passed.

- `git diff --check`: passed.

- Targeted scan:

  `rg` over touched files for common secret tokens, private-content markers, phone-number shapes, raw WDA markers, and private endpoint strings found only the intentional privacy stop phrase in `notes/T002-judge.md`.

## Physical Receipt Attempt

The strongest remaining failure mode is physical-device divergence: the simulator/unit code could be correct while the installed keyboard extension still exposes or accepts `Insert latest` for a stale non-complete snapshot.

Attempted WDA startup on `iPhone-preview` with the repo runbook command:

`xcodebuild -project /Users/neonwatty/.appium/node_modules/appium-xcuitest-driver/node_modules/appium-webdriveragent/WebDriverAgent.xcodeproj -scheme WebDriverAgentRunner-nodebug -destination 'id=00008030-001A0C980A33C02E' -configuration Debug DEVELOPMENT_TEAM=B3A6AN2HA4 CODE_SIGN_STYLE=Automatic PRODUCT_BUNDLE_IDENTIFIER=com.neonwatty.WebDriverAgentRunner -allowProvisioningUpdates test`

Blocker evidence:

- Harness status before startup saw `iPhone-preview` present and WDA project present, but WDA not ready at `http://127.0.0.1:8100`.
- WDA runner launched on device, then emitted: `Timed out while enabling automation mode.`
- The command then prompted for `Password:` and was stopped without entering sensitive credentials.
- `curl` to both `http://127.0.0.1:8100/status` and the prior Wi-Fi endpoint failed before the blocker.

No raw WDA source, screenshot, host-app content, private text, or credential was committed.

## Follow-Up

Add a narrow physical proof task once automation mode is unblocked. The receipt should install the current branch on `iPhone-preview`, stage a stale non-complete App Group snapshot, focus a sterile Notes or Safari field, prove `Insert latest` is disabled/unavailable, then stage a complete snapshot and prove exact-once insertion plus App Group idle cleanup.
