# Release QA Log

Use this file as the release-candidate evidence template. Copy the checklist
below into the release PR or release notes, then fill every result before
publishing.

## Test Command Policy

- `make test` and CI unit tests are deterministic by default and skip
  `GroqTalkTests/LiveGroqIntegrationTests`, even if a local shell or runner
  environment contains stale `RUN_LIVE_GROQ_TESTS` or `GROQ_API_KEY` values.
- Record live Groq API XCTest evidence separately with
  `RUN_LIVE_GROQ_TESTS=1 GROQ_API_KEY=... make test-live-groq`. Do not paste the
  key into this log, PRs, issues, or CI summaries.
- App-level live Groq provider QA remains `make test-provider-qa-live`; live
  local transcription remains `make test-local-transcription-e2e`.

## Release Candidate

- Version: `v1.8.2`
- Commit: `fe4da4e`
- Date: 2026-05-11 09:01:15 MST
- Runner: `jeremywatt`
- macOS version: 26.3.1 (a), build 25D771280a
- Xcode version: Xcode 26.3, build 17C529

## Automated Gates

| Gate | Command | Result | Artifact / notes |
| --- | --- | --- | --- |
| Build with warnings as errors | `xcodebuild build -scheme GroqTalk -configuration Debug -destination 'platform=macOS' OTHER_SWIFT_FLAGS='-warnings-as-errors'` | PASS | `** BUILD SUCCEEDED **` on 2026-05-11 09:01 MST. |
| Unit XCTest suite | `make test` | PASS | xcresult: `Test-GroqTalk-2026.05.11_09-01-41--0700.xcresult`; `** TEST SUCCEEDED **`. |
| UI XCTest suite | `make test-ui` | PASS | xcresult: `Test-GroqTalk-2026.05.11_09-01-56--0700.xcresult`; `** TEST SUCCEEDED **`. |
| Installed app real paste | `make test-paste-real` | SKIP RECORDED | Default run exited `2` on AX-window skip as expected; explicit rerun with `ALLOW_LOCAL_QA_SKIP=1` exited `0`. Production `insertAsync` path was exercised and UI-test bypass was not used, but target AX window was not exposed to the installed app process. |
| Cross-app paste | `make test-cross-app` | PASS WITH SKIPS | TextEdit async paste PASS; SkyLight background paste PASS; Terminal PASS; Chrome PASS; VS Code skipped because app is not installed; Notes skipped to avoid mutating persistent Notes data. |
| Live cleanup quality | `GROQ_API_KEY=... make test-cleanup-quality` | BLOCKED | `make test-cleanup-quality` without `GROQ_API_KEY` failed fast as intended. Rerun with a valid key before release sign-off. |
| Semantic release dry run | `npx semantic-release --dry-run --no-ci` | PASS / NO RELEASE BEFORE TRIGGER | First run failed without `GH_TOKEN`; rerun with `GH_TOKEN="$(gh auth token)"` passed. semantic-release found 3 commits since `v1.8.1`, none release-triggering. PR #48 then added an intentional `fix:` release trigger and published `v1.8.2`. |

## Local-Only Skips

Any skip must include why it was skipped, the command output, and the risk owner.
Do not set `ALLOW_LOCAL_QA_SKIP=1` unless the skipped result is recorded here.

| Gate | Skip reason | Evidence | Owner / follow-up |
| --- | --- | --- | --- |
| Installed app real paste | `/Applications/GroqTalk.app` entered the mock async path, but this desktop session did not expose the TextEdit target AX window to the app process. | `make test-paste-real` exited `2`; `ALLOW_LOCAL_QA_SKIP=1 make test-paste-real` exited `0`. Diagnostics confirmed automation mock request, async path, production `insertAsync`, no UI-test paste queue, automation smoke enabled, and floating status stayed off by default. | Refresh Accessibility permission for `/Applications/GroqTalk.app` and rerun `make test-paste-real` before public release if this skip is not accepted. |
| VS Code cross-app paste | Visual Studio Code.app is not installed on this runner. | `make test-cross-app` reported `VS Code: Visual Studio Code.app not installed`. | Install VS Code and rerun cross-app paste if VS Code coverage is required for the RC. |
| Notes cross-app paste | Test intentionally avoids mutating persistent Notes data from automation. | `make test-cross-app` reported `Notes: Skipped to avoid mutating persistent Notes data from automation`. | Use a disposable Notes account/container or manual Notes smoke test before public release if Notes is a required target. |
| Live cleanup quality | No `GROQ_API_KEY` was present in the shell. | `make test-cleanup-quality` failed with `ERROR: Missing GROQ_API_KEY environment variable.` | Rerun `GROQ_API_KEY=... make test-cleanup-quality` with a valid key before sign-off. |

## Release Artifact Verification

| Artifact | Command | Result | Notes |
| --- | --- | --- | --- |
| DMG signature | `spctl -a -vv -t open --context context:primary-signature GroqTalk-1.8.2-macos.dmg` | PASS | Downloaded from `v1.8.2`; Gatekeeper accepted the DMG as `source=Notarized Developer ID`, origin `Developer ID Application: Mean Weasel LLC (B3A6AN2HA4)`. |
| DMG notarization staple | `xcrun stapler validate GroqTalk-1.8.2-macos.dmg` | PASS | Stapler validation passed for the DMG. Mounted app does not have its own stapled ticket, but `spctl -a -vv /Volumes/GroqTalk/GroqTalk.app` accepted it as Notarized Developer ID and `codesign --verify --deep --strict --verbose=2` passed. |
| DMG checksum | `shasum -a 256 GroqTalk-1.8.2-macos.dmg` | PASS | `b86a6d46d7aa987d6f5724c8aac574e9726c9bbbf1e0114389e49d1b869f2b8b`, matching the GitHub release asset digest. |
| Homebrew cask install | `brew install --cask groqtalk` | BLOCKED | `gh repo view mean-weasel/homebrew-groqtalk` must resolve and the tap cask must match the uploaded DMG checksum before Homebrew is treated as public-ready. README currently treats Homebrew as planned/unverified. |

## Manual Smoke

| Scenario | Result | Notes |
| --- | --- | --- |
| Fresh install from DMG | PASS | Copied `GroqTalk.app` from mounted `GroqTalk-1.8.2-macos.dmg` to `/Applications`, launched successfully, Gatekeeper accepted `/Applications/GroqTalk.app`, bundle version/build `1.8.2` / `32`. |
| Accessibility permission prompt and setup check | PASS | Manual retry on the installed `/Applications/GroqTalk.app` v1.12.0 build succeeded after eliminating a stale Debug/DerivedData process. Diagnostics show `AccessibilityTrust: launch initial=true`, `HotkeyMonitor: start succeeded`, and `SetupHealth: accessibilityTrusted=true`. |
| Microphone permission prompt and setup check | PASS | Manual permission flow succeeded. Diagnostics show `MicrophonePermission: authorizationStatus=0`, followed by `MicrophonePermission: requestAccess granted=true`, then successful audio capture and WAV write. |
| API key save and Keychain readiness | PASS | Manual Groq key Save/Test succeeded. Diagnostics show `validateApiKey: checking provider=groq requiredModels=2` and `validateApiKey: response status=200`. |
| One real transcription | PARTIAL | Installed app captured microphone audio and wrote a WAV after microphone consent. Full end-to-end transcription paste was not separately recorded in this manual step. |
| Paste fallback behavior in a blocked target app | PARTIAL | XCTest covers clipboard fallback restoration for terminated target. Manual blocked-target app smoke not run. |
| Clear History removes retained retry audio | PASS (TARGETED) | `xcodebuild test -scheme GroqTalk -configuration Debug -destination 'platform=macOS' -parallel-testing-enabled NO -maximum-concurrent-test-device-destinations 1 -enableCodeCoverage NO -only-testing:GroqTalkTests/TranscriptionHistoryTests` passed in `Test-GroqTalk-2026.05.21_12-44-28--0700.xcresult`. The suite verifies failed audio is moved into `retry-audio`, survives reload for retry, and is removed by delete, clear history, retry resolution, retained-audio clear, and retention trimming. |

## Open Beta Readiness Continuation

| Gate | Command | Result | Artifact / notes |
| --- | --- | --- | --- |
| Unit XCTest suite after open-beta readiness changes | `make test` | PASS | xcresult: `Test-GroqTalk-2026.05.21_11-57-23--0700.xcresult`; `** TEST SUCCEEDED **`. |
| Provider setup UI QA | `make test-provider-qa` | PASS | xcresult: `Test-GroqTalk-2026.05.21_11-42-37--0700.xcresult`; all seven provider QA tests passed, including Groq default, Local whisper.cpp selection/setup/persistence, invalid custom URL, and custom provider persistence. |
| Full UI XCTest suite after open-beta readiness changes | `make test-ui` | BLOCKED | Bounded local run exceeded 600 seconds and left `Test-GroqTalk-2026.05.21_11-46-41--0700.xcresult` incomplete/corrupt with no readable `Info.plist`. No lingering `xcodebuild`, `GroqTalkUITests`, or `GroqTalk.app` processes remained afterward. Rerun on a healthy idle UI automation session or complete equivalent manual smoke before beta sign-off. |
| Focused open-beta UI smoke | `xcodebuild test ... -only-testing:GroqTalkUITests/GroqTalkUITests/testSetupCheckCanBeRunInline ... testSettingsCanOpenSpecificTabs` | PASS | xcresult: `Test-GroqTalk-2026.05.21_12-07-37--0700.xcresult`; 14 selected UI tests passed covering setup recovery, microphone setup states, onboarding completion, local-provider onboarding without API key, history search/filter/failure retry visibility, floating status, and settings tab routing. |
| Focused transcription cancel and hotkey accessibility UI smoke | `xcodebuild test ... -only-testing:GroqTalkUITests/GroqTalkUITests/testTranscribingStateShowsCancelTranscriptionAction -only-testing:GroqTalkUITests/GroqTalkUITests/testCustomHotkeyRecorderIsAccessibleButton` | PASS | xcresult: `Test-GroqTalk-2026.05.21_12-18-04--0700.xcresult`; verified the transcribing state exposes an enabled `Cancel transcription` control that returns the session to Ready, and verified the custom hotkey recorder is exposed as an enabled accessibility button with the custom shortcut label. |
| Unit XCTest suite after focused UI harness additions | `make test` | PASS | xcresult: `Test-GroqTalk-2026.05.21_12-18-44--0700.xcresult`; `** TEST SUCCEEDED **`. |
| Focused secondary UX UI smoke | `xcodebuild test ... -only-testing:GroqTalkUITests/GroqTalkUITests/testHistoryWindowOpensAndSearchesSeededRecords -only-testing:GroqTalkUITests/GroqTalkUITests/testFloatingWarningShowsExpandedClipboardContext -only-testing:GroqTalkUITests/GroqTalkUITests/testHelpButtonTargetsCanonicalTroubleshootingURL -only-testing:GroqTalkUITests/GroqTalkUITests/testCustomHotkeyRecorderIsAccessibleButton` | PASS | xcresult: `Test-GroqTalk-2026.05.21_12-35-58--0700.xcresult`; verified history search and no-match empty state, floating warning title/detail/clipboard context, canonical troubleshooting Help URL capture, and custom hotkey recorder accessibility. |
| Unit XCTest suite after secondary UX UI harness additions | `make test` | PASS | xcresult: `Test-GroqTalk-2026.05.21_12-37-08--0700.xcresult`; `** TEST SUCCEEDED **`. |
| Focused retained retry-audio cleanup suite | `xcodebuild test -scheme GroqTalk -configuration Debug -destination 'platform=macOS' -parallel-testing-enabled NO -maximum-concurrent-test-device-destinations 1 -enableCodeCoverage NO -only-testing:GroqTalkTests/TranscriptionHistoryTests` | PASS | xcresult: `Test-GroqTalk-2026.05.21_12-44-28--0700.xcresult`; 43 history tests passed, including retained `retry-audio` persistence, delete, clear history, clear retained audio, retry resolution, and retention trimming cleanup. |
| Unit XCTest suite after retained-audio assertion tightening | `make test` | PASS | xcresult: `Test-GroqTalk-2026.05.21_12-44-46--0700.xcresult`; `** TEST SUCCEEDED **`. |
| Focused Keychain storage suite | `xcodebuild test -scheme GroqTalk -configuration Debug -destination 'platform=macOS' -parallel-testing-enabled NO -maximum-concurrent-test-device-destinations 1 -enableCodeCoverage NO -only-testing:GroqTalkTests/KeychainHelperTests` | PASS | xcresult: `Test-GroqTalk-2026.05.21_12-46-38--0700.xcresult`; 12 Keychain tests passed covering save/read, overwrite, delete, whitespace trimming, provider-scoped Groq/custom keys, and legacy plaintext migration/removal. Live installed-app Save/Test still requires a real or disposable Groq API key. |
| Live cleanup quality after open-beta readiness changes | `GROQ_API_KEY="$(security find-generic-password -a groq-api-key -w)" make test-cleanup-quality` | PASS | Used the local Keychain Groq key without printing it. Both Clean up and Rewrite clearly returned non-empty text and preserved the required core facts: tomorrow, demo, async paste, Chrome, Terminal, TextEdit, video, and GroqTalk. |
| Homebrew tap availability | `gh repo view mean-weasel/homebrew-groqtalk --json nameWithOwner,url,visibility` | PASS | Public tap exists at `https://github.com/mean-weasel/homebrew-groqtalk`. |
| Homebrew cask metadata | `gh api repos/mean-weasel/homebrew-groqtalk/contents/Casks/groqtalk.rb` | PASS | Cask version is `1.12.0`; URL points to `https://github.com/mean-weasel/groqtalk/releases/download/v1.12.0/GroqTalk-1.12.0-macos.dmg`; `sha256` is `2f630fee780760bc3f0aef8a5d2aecbfbcd88d357cf5c7317d76b2a74991bd18`, matching the GitHub release asset digest. |
| Clean Homebrew cask install and launch smoke | `brew tap mean-weasel/groqtalk https://github.com/mean-weasel/homebrew-groqtalk`; `brew install --cask --appdir=/tmp/groqtalk-brew-apps-74647 groqtalk`; launch `GroqTalk.app` with `--ui-testing --reset-defaults --seed-history`; `brew uninstall --cask groqtalk`; `brew untap mean-weasel/groqtalk` | PASS | Installed cask `groqtalk` version `1.12.0` build `42` into a temporary app dir, launched successfully, `spctl` accepted the app as Notarized Developer ID, and `codesign --verify --deep --strict --verbose=2` passed. Cleanup removed the cask/temp app and restored the tap state. Existing `/Applications/GroqTalk.app` remained version `1.8.2` build `32`. |
| `/Applications` v1.12.0 cask install and launch | `brew tap mean-weasel/groqtalk https://github.com/mean-weasel/homebrew-groqtalk`; move existing `/Applications/GroqTalk.app` aside; `brew install --cask groqtalk`; `open -a /Applications/GroqTalk.app`; PlistBuddy version/build; `spctl --assess --type execute --verbose=4`; `codesign --verify --deep --strict --verbose=2` | PASS | Installed `/Applications/GroqTalk.app` is version `1.12.0` build `42`, launched successfully, `spctl` accepted it as `source=Notarized Developer ID`, and deep strict codesign verification passed. The previous `1.8.2` build `32` app was moved to `/tmp/groqtalk-app-backups/`. |
| Local permissions QA precheck | `make prepare-local-permissions-qa-check` | PASS WITH WARNINGS | Non-mutating check passed for the installed `/Applications/GroqTalk.app` v1.12.0 bundle. It verified bundle id `com.neonwatty.GroqTalk`, executable, microphone usage description, Developer ID authority `Mean Weasel LLC (B3A6AN2HA4)`, and codesign team id `B3A6AN2HA4`. The only warning was that GroqTalk was running; macOS still requires manual Accessibility/Input Monitoring/Microphone consent and Test Setup. |
| Guided installed-app permissions QA helper | `make guide-installed-permissions-qa` | PASS WITH WARNINGS | Verified `/Applications/GroqTalk.app` version `1.12.0` build `42`, Developer ID signing, microphone usage description, launched GroqTalk, opened Accessibility, Input Monitoring, and Microphone privacy panes, and printed the release-smoke checklist. The only warning was that GroqTalk was already running; consent toggles and API-key Save/Test remain manual. |
| Guided helper wrong-process guard | `make test-local-permissions-qa-script`; `make guide-installed-permissions-qa`; process inspection with `ps` | PASS | Helper now distinguishes a running `/Applications/GroqTalk.app` release process from a Debug/DerivedData process and fails guide mode when the wrong GroqTalk binary is active. Shell tests passed. Live guide confirmed the active process is `/Applications/GroqTalk.app/Contents/MacOS/GroqTalk`. |
| Accessibility retry diagnostics | `/usr/bin/log stream --debug ... com.apple.TCC ...`; `tail ~/Library/Application\\ Support/GroqTalk/Diagnostics/groqtalk.log` | PASS / MIC REMAINS | TCC attribution capture emitted no decision events during the setup check, but GroqTalk diagnostics show the release app reached `AccessibilityTrust: launch initial=true`, `HotkeyMonitor: start succeeded`, and later `SetupHealth: accessibilityTrusted=true`. The same setup check still reports `microphone=notDetermined`, so remaining permission work is Microphone rather than Accessibility. |
| Manual fresh-install permission/API smoke | Installed `/Applications/GroqTalk.app` v1.12.0; manual Accessibility and Microphone consent; Groq API-key Save/Test; Test Setup / recording path | PASS | User reported the flow worked. Diagnostics from the installed release process show Accessibility trusted, hotkey monitor started, Groq API validation returned HTTP 200, microphone access request was granted, and audio capture wrote `groqtalk-6A652BA7-ED8A-4427-BC0B-664CDE368CEC.wav`. |
| Latest release assets | `gh release view --repo mean-weasel/groqtalk --json tagName,url,assets,publishedAt,isDraft,isPrerelease,targetCommitish` | PARTIAL | Latest release `v1.12.0` is published with `GroqTalk-1.12.0-macos.dmg` and `appcast.xml`. No separate `GroqTalk-1.12.0-macos.dmg.sha256` asset is present; README now allows verification against the GitHub release asset digest or a `.sha256` file when published. |
| Sparkle appcast asset | `gh release download v1.12.0 --repo mean-weasel/groqtalk --pattern appcast.xml` | PASS | `appcast.xml` points at `https://github.com/mean-weasel/groqtalk/releases/download/v1.12.0/GroqTalk-1.12.0-macos.dmg`, version `1.12.0`, build `42`, minimum macOS `14.0`. |
| v1.12.0 DMG checksum/signature/notarization | `gh release download v1.12.0 --repo mean-weasel/groqtalk --pattern GroqTalk-1.12.0-macos.dmg`; `shasum -a 256`; `spctl -a -vv -t open --context context:primary-signature`; `xcrun stapler validate` | PASS | SHA-256 is `2f630fee780760bc3f0aef8a5d2aecbfbcd88d357cf5c7317d76b2a74991bd18`, matching the GitHub release asset digest and Homebrew cask. Gatekeeper accepted the DMG as `source=Notarized Developer ID`, origin `Developer ID Application: Mean Weasel LLC (B3A6AN2HA4)`. Stapler validation passed. |
| v1.12.0 mounted app signature | `hdiutil attach -readonly -nobrowse`; `spctl -a -vv`; `codesign --verify --deep --strict --verbose=2`; `hdiutil detach` | PASS | Mounted `GroqTalk.app` was accepted as Notarized Developer ID and `codesign` validated the app, Sparkle framework, updater app, and XPC services. The DMG was detached afterward. |

## v1.12.1 Post-Release Validation

| Gate | Command | Result | Artifact / notes |
| --- | --- | --- | --- |
| GitHub release assets | `gh release view v1.12.1 --repo mean-weasel/groqtalk --json tagName,url,assets,publishedAt,isDraft,isPrerelease,targetCommitish` | PASS | Release `v1.12.1` is published, not draft, not prerelease, and includes `GroqTalk-1.12.1-macos.dmg`, `GroqTalk-1.12.1-macos.dmg.sha256`, and `appcast.xml`. |
| Homebrew cask metadata | `gh api repos/mean-weasel/homebrew-groqtalk/contents/Casks/groqtalk.rb` | PASS | Cask version is `1.12.1`; URL points to `https://github.com/mean-weasel/groqtalk/releases/download/v1.12.1/GroqTalk-1.12.1-macos.dmg`; `sha256` is `4e3551cc66bda43191e2a73db61273f83d2fa50b2f26ddd85851f539f2298f9e`, matching the GitHub release asset digest and downloaded DMG. |
| `/Applications` cask reinstall | `brew update && brew reinstall mean-weasel/groqtalk/groqtalk` | PASS | Homebrew updated the `mean-weasel/groqtalk` tap, removed the previous `1.12.0` app, and installed `/Applications/GroqTalk.app` from cask `1.12.1`. |
| Installed app identity and signing | `PlistBuddy`; `codesign --verify --deep --strict --verbose=2`; `spctl -a -vv -t execute /Applications/GroqTalk.app` | PASS | Installed app is version `1.12.1` build `33`. Deep strict codesign verification passed for the app, Sparkle framework, updater app, and XPC services. Gatekeeper accepted the installed app as `source=Notarized Developer ID`, origin `Developer ID Application: Mean Weasel LLC (B3A6AN2HA4)`. |
| Installed app staple check | `xcrun stapler validate /Applications/GroqTalk.app` | INFO | The copied app bundle does not have its own stapled ticket. This matches the shipped artifact model verified below: the distributed DMG is stapled and Gatekeeper accepts the installed app as Notarized Developer ID. |
| DMG checksum/signature/notarization | `gh release download v1.12.1 --repo mean-weasel/groqtalk --pattern 'GroqTalk-1.12.1-macos.dmg' --pattern 'GroqTalk-1.12.1-macos.dmg.sha256'`; `shasum -a 256`; `spctl -a -vv -t open --context context:primary-signature`; `xcrun stapler validate` | PASS | SHA-256 is `4e3551cc66bda43191e2a73db61273f83d2fa50b2f26ddd85851f539f2298f9e`, matching the `.sha256` asset, GitHub release digest, and Homebrew cask. Gatekeeper accepted the DMG as `source=Notarized Developer ID`; stapler validation passed. |
| Sparkle appcast asset | `gh release download v1.12.1 --repo mean-weasel/groqtalk --pattern appcast.xml`; `xmllint --xpath ...` | PASS | `appcast.xml` points at `https://github.com/mean-weasel/groqtalk/releases/download/v1.12.1/GroqTalk-1.12.1-macos.dmg`, version `1.12.1`, build `33`, minimum macOS `14.0`, enclosure length `2299681`. |
| Guided installed-app permissions QA helper | `make guide-installed-permissions-qa` | PASS | Helper now derives expected version/build from the Xcode project. It verified `/Applications/GroqTalk.app` version `1.12.1` build `33`, bundle id, executable, microphone usage description, Developer ID signing, and team id; launched GroqTalk; opened Accessibility, Input Monitoring, and Microphone privacy panes; and printed the manual release-smoke checklist with 0 warnings. |
| Guided helper shell tests | `make test-local-permissions-qa-script`; `make -n guide-installed-permissions-qa` | PASS | Shell tests passed. Dry run shows `EXPECTED_VERSION="1.12.1" EXPECTED_BUILD="33" scripts/prepare-local-permissions-qa.sh --guide-installed`, preventing stale expected release values in future QA runs. |
| Installed app launch/setup diagnostics | `tail ~/Library/Application\\ Support/GroqTalk/Diagnostics/groqtalk.log`; `ps` | PASS | `/Applications/GroqTalk.app/Contents/MacOS/GroqTalk` launched. Diagnostics show `applicationDidFinishLaunching`, updater/controllers/hotkey configured, `AccessibilityTrust: launch initial=true`, `HotkeyMonitor: start succeeded`, `SetupHealth: accessibilityTrusted=true`, `SetupHealth: microphone=authorized`, and API key state refresh completed. |
| Manual first-run consent/API smoke | User-driven in GroqTalk after helper opens privacy panes | NOT RERUN | macOS consent toggles and Groq API-key Save/Test remain manual. Existing diagnostics confirm the installed `1.12.1` app launched with Accessibility trusted and Microphone authorized; perform a fresh-profile manual Save/Test and hold-to-record smoke if beta sign-off requires new consent prompts rather than retained local grants. |

## Sign-Off

- Known P0/P1 issues: None from CI/local deterministic gates, `v1.12.1` release workflow, DMG verification, Homebrew cask reinstall, installed-app signing/Gatekeeper checks, or installed-app launch/setup diagnostics.
- Remaining P2/P3 issues accepted for this release: Installed-app paste AX-window skip on this runner; VS Code/Notes cross-app coverage skipped.
- Approver:
