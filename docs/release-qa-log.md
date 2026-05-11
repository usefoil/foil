# Release QA Log

Use this file as the release-candidate evidence template. Copy the checklist
below into the release PR or release notes, then fill every result before
publishing.

## Release Candidate

- Version:
- Commit:
- Date:
- Runner:
- macOS version:
- Xcode version:

## Automated Gates

| Gate | Command | Result | Artifact / notes |
| --- | --- | --- | --- |
| Build with warnings as errors | `xcodebuild build -scheme GroqTalk -configuration Debug -destination 'platform=macOS' OTHER_SWIFT_FLAGS='-warnings-as-errors'` |  |  |
| Unit XCTest suite | `make test` |  |  |
| UI XCTest suite | `make test-ui` |  |  |
| Installed app real paste | `make test-paste-real` |  |  |
| Cross-app paste | `make test-cross-app` |  |  |
| Live cleanup quality | `GROQ_API_KEY=... make test-cleanup-quality` |  |  |
| Semantic release dry run | `npx semantic-release --dry-run --no-ci` |  |  |

## Local-Only Skips

Any skip must include why it was skipped, the command output, and the risk owner.
Do not set `ALLOW_LOCAL_QA_SKIP=1` unless the skipped result is recorded here.

| Gate | Skip reason | Evidence | Owner / follow-up |
| --- | --- | --- | --- |
|  |  |  |  |

## Release Artifact Verification

| Artifact | Command | Result | Notes |
| --- | --- | --- | --- |
| DMG signature | `spctl -a -vv -t open --context context:primary-signature GroqTalk-VERSION-macos.dmg` |  |  |
| DMG notarization staple | `xcrun stapler validate /Volumes/GroqTalk/GroqTalk.app` |  |  |
| DMG checksum | `shasum -a 256 GroqTalk-VERSION-macos.dmg` |  |  |
| Homebrew cask install | `brew install --cask groqtalk` |  |  |

## Manual Smoke

| Scenario | Result | Notes |
| --- | --- | --- |
| Fresh install from DMG |  |  |
| Accessibility permission prompt and setup check |  |  |
| Microphone permission prompt and setup check |  |  |
| API key save and Keychain readiness |  |  |
| One real transcription |  |  |
| Paste fallback behavior in a blocked target app |  |  |
| Clear History removes retained retry audio |  |  |

## Sign-Off

- Known P0/P1 issues:
- Remaining P2/P3 issues accepted for this release:
- Approver:
