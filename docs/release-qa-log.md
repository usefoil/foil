# Release QA Log

Use this file as the release-candidate evidence template. Copy the checklist
below into the release PR or release notes, then fill every result before
publishing.

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
| Homebrew cask install | `brew install --cask groqtalk` | BLOCKED | `gh repo view neonwatty/tap` could not resolve the tap repository. README correctly treats Homebrew as planned/unverified. |

## Manual Smoke

| Scenario | Result | Notes |
| --- | --- | --- |
| Fresh install from DMG | PASS | Copied `GroqTalk.app` from mounted `GroqTalk-1.8.2-macos.dmg` to `/Applications`, launched successfully, Gatekeeper accepted `/Applications/GroqTalk.app`, bundle version/build `1.8.2` / `32`. |
| Accessibility permission prompt and setup check | PARTIAL | Installed signed app launches from `/Applications`; AX-window exposure was unavailable earlier for real paste smoke. Requires fresh permission-cycle verification. |
| Microphone permission prompt and setup check | NOT RUN | Requires manual fresh-user state or clean permission reset. |
| API key save and Keychain readiness | NOT RUN | Requires manual app flow with a real or disposable key. |
| One real transcription | NOT RUN | Requires `GROQ_API_KEY` or app-saved key plus microphone input. |
| Paste fallback behavior in a blocked target app | PARTIAL | XCTest covers clipboard fallback restoration for terminated target. Manual blocked-target app smoke not run. |
| Clear History removes retained retry audio | NOT RUN | Requires manual retained-audio scenario or targeted integration test. |

## Sign-Off

- Known P0/P1 issues: None from CI/local deterministic gates or DMG verification. RC sign-off is still blocked on live cleanup quality and remaining manual smoke.
- Remaining P2/P3 issues accepted for this release: Installed-app paste AX-window skip on this runner; VS Code/Notes cross-app coverage skipped; Homebrew tap unavailable.
- Approver:
