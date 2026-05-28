# Queued Paste Compatibility Smoke

This runbook records the issue 159 compatibility smoke for queued paste. It is
intentionally local-only because target capture, app activation, Accessibility,
and browser text-entry behavior depend on the active macOS desktop session.

## Scope

This smoke is for the experimental queued-paste workflow:

- Verify that target identity is app/window based, not a stored screen point.
- Cover TextEdit and disposable browser text-entry targets.
- Record fallback or unavailable-target behavior.
- Verify delivery through the user-facing queued-paste delivery hotkey.

Out of scope:

- Overlapping recording or overlapping transcription architecture.
- Release packaging or distribution checks.

## What Must Be Recorded

Each target row must record:

- Target app and target surface.
- Captured identity signal: app name, pid, and window/title/window ID when
  observable.
- Whether the transcript was queued before delivery.
- Delivery action used: queued-paste delivery hotkey, Paste Next, or Drain Queue.
- Whether text landed in the intended target app/window.
- Whether the app returned focus as expected.
- Fallback behavior for unavailable targets, or the exact reason fallback could
  not be exercised.
- Evidence: command, log path, screenshot path, or manual transcript notes.

## Local Command

Run:

```sh
make test-queued-paste-compatibility
```

This command runs the available local target-identity gates and writes logs under
`/tmp/foil-queued-paste-compatibility-*`.

The wrapper also runs `make prepare-local-permissions-qa-check` after installing
`/Applications/Foil.app`. If that precheck reports a signing identifier mismatch
or ad-hoc signing, treat subsequent installed-app Accessibility failures as a
local TCC identity problem until the app is reinstalled with a trusted signing
identity and macOS privacy consent is refreshed.

Important: the command is a visible desktop harness. It uses an automation hook
only to enqueue a mock transcript against the real frontmost target, then
delivers through Foil's user-facing queued-paste delivery hotkey.

## Manual Queued-Paste Procedure

Use disposable targets only.

1. Install and launch the debug or installed Foil app.
2. Enable `Queue transcriptions for later paste` in Experimental settings.
3. Enable mock transcription if using a debug build; otherwise use a short real
   recording.
4. Open the target app and place the cursor in the target text field.
5. Start and stop a transcription while the target app/window is frontmost.
6. Confirm Foil shows `Transcript queued`.
7. Move focus away from the target app/window.
8. Use Foil's queued-paste delivery hotkey.
9. Confirm the text lands in the original target app/window.
10. Record app/window identity behavior and evidence in the matrix.

For fallback:

1. Repeat the same capture and queue steps.
2. Close the target window or quit the target app before `Paste Next`.
3. Use `Paste Next`.
4. Record whether the item becomes manual-paste/fallback, whether text is copied
   to the clipboard, and the user-visible recovery path.

## Compatibility Matrix

| Target | Procedure | Target identity evidence | Queued evidence | Result | Evidence / notes |
| --- | --- | --- | --- | --- | --- |
| TextEdit disposable document | Automation hook plus prerequisite command `ALLOW_LOCAL_QA_SKIP=1 make test-queued-paste-compatibility` | Prerequisite evidence from `tests/test_async_paste.swift`: captured `TextEdit pid=26348` with a window element and pasted into `AsyncPasteTestA.txt`, not the current `AsyncPasteTestB.txt`; `tests/test_skylight_paste.swift` captured `TextEdit wid=123587` and pasted while Finder stayed frontmost. Foil's installed-app automation captured `TextEdit pid=29687` but no AX window because `accessibilityTrusted=false` for `/Applications/Foil.app` in this session. | `tests/test_queued_paste_compatibility.swift` triggered `QueuedPaste.enqueue: status=pending target=TextEdit`, then `QueuedPaste.deliver` and `automation queued smoke: deliver next result=original app command posted`. | Failed in this desktop session: queued item delivered according to Foil, but text did not land in the TextEdit target. | Artifact: `/tmp/foil-queued-paste-compatibility-20260528-043456/queued-real-targets.log`. Follow-up: refresh/grant Accessibility/Input Monitoring for `/Applications/Foil.app`, then rerun. |
| Browser text field | Automation hook plus prerequisite command `ALLOW_LOCAL_QA_SKIP=1 make test-queued-paste-compatibility` | Prerequisite evidence from `make test-cross-app`: Chrome textarea target passed, with text reaching the captured textarea and frontmost after paste reported as `Google Chrome`. Foil's installed-app automation captured `Google Chrome pid=30174` but no AX window because `accessibilityTrusted=false` for `/Applications/Foil.app` in this session. | `tests/test_queued_paste_compatibility.swift` triggered `QueuedPaste.enqueue: status=pending target=Google Chrome`, then `QueuedPaste.deliver` and `automation queued smoke: deliver next result=original app command posted`. | Failed in this desktop session: queued item delivered according to Foil, but text did not land in the Chrome textarea. | Artifact: `/tmp/foil-queued-paste-compatibility-20260528-043456/queued-real-targets.log`. Follow-up: refresh/grant Accessibility/Input Monitoring for `/Applications/Foil.app`, then rerun. |
| Closed/unavailable target | Automation hook in `tests/test_queued_paste_compatibility.swift` | Captured TextEdit target before quitting TextEdit. | `QueuedPaste.enqueue: status=pending target=TextEdit`, followed by target process termination before delivery. | Passed: delivery returned clipboard fallback and the clipboard contained the queued transcript text. | Artifact: `/tmp/foil-queued-paste-compatibility-20260528-043456/queued-real-targets.log`. |

## 2026-05-28 Trusted-App Product-Fix Rerun

Command:

```sh
swiftc -parse tests/test_queued_paste_compatibility.swift
xcodebuild test -scheme Foil -configuration Debug -destination 'platform=macOS' -parallel-testing-enabled NO -maximum-concurrent-test-device-destinations 1 -enableCodeCoverage NO -only-testing:FoilTests/BackgroundPasteTests
make prepare-local-permissions-qa-check
ALLOW_LOCAL_QA_SKIP=1 make test-queued-paste-compatibility
```

Result: pass. The queued compatibility command wrote artifacts to
`/tmp/foil-queued-paste-compatibility-20260528-081907`.

Observed:

- `make prepare-local-permissions-qa-check` passed for `/Applications/Foil.app`
  with bundle id `com.neonwatty.Foil` and authority `Foil Local Code Signing`.
- Foil diagnostics showed `SetupHealth: accessibilityTrusted=true`.
- The focused `FoilTests/BackgroundPasteTests` suite passed 14 tests, including
  the new guard that rejects unchanged AX text values.
- TextEdit queued delivery passed for `TextEdit pid=57807`, title
  `FoilQueuedTextEditTarget.txt`.
- Chrome queued delivery passed for `Google Chrome pid=76811`, title
  `Foil Queued Chrome Target - Google Chrome - Jeremy`.
- Unavailable-target fallback passed and verified the clipboard contained the
  queued transcript text.
- Chrome diagnostics showed direct AX selected-text insertion reported success
  but did not change the value, so Foil fell through to Tier 2 choreography and
  delivered via `original app command posted`.

Conclusion: after refreshing Accessibility for the signed installed app and
tightening AX insertion verification, the real-target queued-paste smoke passes
TextEdit, Chrome, and unavailable-target fallback without closing Chrome tabs or
quitting Chrome.

## 2026-05-28 Browser/Fallback Expansion Rerun

Command:

```sh
swiftc -parse tests/test_queued_paste_compatibility.swift
swiftc -parse tests/test_cross_app_async_paste.swift
xcodebuild test -scheme Foil -configuration Debug -destination 'platform=macOS' -parallel-testing-enabled NO -maximum-concurrent-test-device-destinations 1 -enableCodeCoverage NO -only-testing:FoilTests/QueuedPasteTests
ALLOW_LOCAL_QA_SKIP=1 make test-queued-paste-compatibility
```

Result: pass with one optional browser skip. The queued compatibility command
wrote artifacts to `/tmp/foil-queued-paste-compatibility-20260528-091151`.

Observed:

- The prerequisite cross-app Chrome row passed and no longer closes the active
  Chrome tab after verification.
- TextEdit queued delivery passed for `TextEdit pid=62707`, title
  `FoilQueuedTextEditTarget.txt`.
- Chrome queued delivery passed for the existing Chrome process
  `Google Chrome pid=76811`, title
  `Foil Queued Chrome Target - Google Chrome - Jeremy`, with `noTabClose=true`.
- Firefox is installed, but its disposable local-file target exposed a
  `Problem loading page` window instead of the test page, so the optional row
  was recorded as a skip rather than writing into an arbitrary Firefox page.
- Safari queued delivery passed for `Safari pid=62276`, title
  `Foil Queued Safari Target`, with `noTabClose=true`.
- Unavailable-target fallback passed, verified the clipboard contained the
  queued transcript text, and recorded the recovery message
  `Target unavailable; text copied to clipboard`.

Conclusion: the experimental queued-paste smoke now records an additional
browser target when available, avoids closing browser tabs in the compatibility
path, and captures the manual-paste recovery message for unavailable targets.

## 2026-05-28 Localhost Browser/Fallback Rerun

Command:

```sh
swiftc -parse tests/test_queued_paste_compatibility.swift
swiftc -parse tests/test_cross_app_async_paste.swift
xcodebuild test -scheme Foil -configuration Debug -destination 'platform=macOS' -parallel-testing-enabled NO -maximum-concurrent-test-device-destinations 1 -enableCodeCoverage NO -only-testing:FoilTests/QueuedPasteTests
ALLOW_LOCAL_QA_SKIP=1 make test-queued-paste-compatibility
```

Result: pass. The queued compatibility command wrote artifacts to
`/tmp/foil-queued-paste-compatibility-20260528-095356`; the focused XCTest
result is `Test-Foil-2026.05.28_09-51-55--0700.xcresult`.

Observed:

- The prerequisite cross-app Chrome row passed against a disposable localhost
  target with `privateMode=requested`, `no tab close`, and `no browser quit`.
- TextEdit queued delivery passed for `TextEdit pid=66632`, title
  `FoilQueuedTextEditTarget.txt`.
- Chrome queued delivery passed for the existing Chrome process
  `Google Chrome pid=76811`, title
  `Foil Queued Chrome Target - Google Chrome (Incognito)`, with
  `transport=localhost`, `privateMode=requested`, `reusedExistingProcess=true`,
  `noTabClose=true`, and `noUserBrowserQuit=true`.
- Firefox queued delivery passed for the existing Firefox process
  `Firefox pid=61995`, title
  `Foil Queued Firefox Target — Private Browsing`, with `transport=localhost`,
  `privateMode=requested`, `reusedExistingProcess=true`, `noTabClose=true`, and
  `noUserBrowserQuit=true`. The disposable page title changes after input so
  Firefox can be verified without reading an AX textarea value that Firefox does
  not expose in this private-window configuration.
- Safari queued delivery passed for `Safari pid=62276`, title
  `Foil Queued Safari Target`, with `transport=localhost`,
  `privateMode=notRequested`, `reusedExistingProcess=true`, `noTabClose=true`,
  and `noUserBrowserQuit=true`.
- Unavailable-target fallback passed, verified the clipboard contained the
  queued transcript text, and recorded the recovery message
  `Target unavailable; text copied to clipboard`.

Conclusion: the local-file Firefox skip is resolved by serving disposable
browser targets from localhost. Chrome and Firefox request private windows to
avoid persistent profile history/content changes where the browser supports it;
Safari remains an optional disposable-localhost row with no automated tab close
or browser quit path.

## 2026-05-28 Local Rerun

Command:

```sh
ALLOW_LOCAL_QA_SKIP=1 make test-queued-paste-compatibility
```

Result: failed with one prerequisite gate failure. The command wrote artifacts to
`/tmp/foil-queued-paste-compatibility-20260528-044803`.

Observed:

- The installed-app TextEdit path again reached the production async paste path
  and was recorded as an explicit local AX skip.
- `make test-cross-app` passed TextEdit async paste, SkyLight background paste,
  Terminal, and Chrome textarea checks.
- `tests/test_queued_paste_compatibility.swift` enqueued and delivered queued
  items for TextEdit pid `39669` and Google Chrome pid `76811`, but text did not
  land in either target.
- Unavailable-target fallback passed and verified the clipboard contained the
  queued transcript text.
- `make prepare-local-permissions-qa-check` failed after the run because the
  installed app's `Info.plist` bundle id is `com.neonwatty.Foil`, while
  `codesign` reports identifier `Foil` with ad-hoc signing and no team id. This
  explains why `/Applications/Foil.app` launched with
  `SetupHealth: accessibilityTrusted=false` despite local permission history.

Conclusion: this rerun confirms the automation hook and fallback behavior, but
the TextEdit and browser success rows still require reinstalling with a trusted
signing identity, refreshing macOS Accessibility/Input Monitoring consent for
`/Applications/Foil.app`, and rerunning the smoke.

## 2026-05-28 Signed-App Rerun

Command:

```sh
make setup-local-signing LOCAL_SIGN_KEYCHAIN_PASSWORD=foil-local-codesign
security unlock-keychain -p foil-local-codesign ~/Library/Keychains/foil-codesign.keychain-db
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k foil-local-codesign ~/Library/Keychains/foil-codesign.keychain-db
make install SIGN_IDENTITY="Foil Local Code Signing" LOCAL_SIGN_KEYCHAIN_PASSWORD=foil-local-codesign
ALLOW_LOCAL_QA_SKIP=1 make test-queued-paste-compatibility
```

Result: failed with one prerequisite gate failure. The command wrote artifacts to
`/tmp/foil-queued-paste-compatibility-20260528-050432`.

Observed:

- The installed app identity is now coherent: `codesign` reports
  `Identifier=com.neonwatty.Foil` with authority `Foil Local Code Signing`, and
  `make prepare-local-permissions-qa-check` passed with local-signing warnings.
- The installed-app TextEdit path still skipped because the running Foil process
  did not receive the target AX window.
- Foil diagnostics still show `SetupHealth: accessibilityTrusted=false`.
- `make test-cross-app` passed TextEdit async paste, SkyLight background paste,
  Terminal, and Chrome textarea checks.
- `tests/test_queued_paste_compatibility.swift` enqueued and delivered queued
  items for TextEdit pid `41791` and Google Chrome pid `76811`, but text did not
  land in either target.
- Unavailable-target fallback passed and verified the clipboard contained the
  queued transcript text.

Conclusion: the local signing/TCC identity mismatch is fixed. The remaining
blocker is macOS Accessibility/Input Monitoring consent for the newly signed
`/Applications/Foil.app` identity.

## 2026-05-28 Local Evidence

Command:

```sh
ALLOW_LOCAL_QA_SKIP=1 make test-queued-paste-compatibility
```

Result: pass with explicit local skip. The command wrote artifacts to
`/tmp/foil-queued-paste-compatibility-20260528-042455`.

Observed:

- `make test-paste-real` built and installed `/Applications/Foil.app`, posted
  the automation mock transcription request, observed the async paste path,
  exercised production `TextInserter.insertAsync`, and avoided the UI-test paste
  bypass.
- The installed-app TextEdit gate skipped because this desktop session did not
  expose the target AX window to the app process.
- `make test-cross-app` passed its TextEdit async paste, SkyLight background
  paste, Terminal, and Chrome textarea checks.
- VS Code was skipped because it is not installed.
- Notes was skipped by design to avoid mutating persistent Notes data.

Conclusion: target app/window capture and browser text-field paste mechanics
have local prerequisite evidence. The oracle still needs a manual real-target
queued-paste row or a later product test hook because the current queued
automation path uses a synthetic Foil target.

## Follow-Up Rules

Create a follow-up when:

- Text reaches the clipboard but not the intended app/window.
- The queue cannot distinguish target unavailable from paste failure.
- Browser text fields need app-specific activation or focus handling.
- A fully automated real-target queued smoke needs additional disposable target coverage.

Do not fold overlapping transcription into this tranche.
