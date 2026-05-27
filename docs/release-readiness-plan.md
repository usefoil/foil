# Foil Release Readiness Plan

This document records the current remediation plan for moving Foil from early beta quality toward a credible public release. It is intended as the shared reference before implementation begins.

## XCTest QA Standard

XCTest coverage is the gold standard for deciding whether a feature works. A change is not considered complete because the code compiles, the UI looks correct, or a manual check happened to pass once. Each feature or fix should include deterministic XCTest coverage at the lowest practical level, plus UI or integration coverage when user-visible behavior depends on macOS app state.

### Definition of Done

Every implementation task should include:

- Unit tests for pure logic, state transitions, persistence, request construction, error mapping, and concurrency behavior.
- UI tests for visible menu, settings, onboarding, history, and feedback flows.
- Integration or local QA tests for OS-bound behavior that cannot be fully proven in CI, especially paste, focus, Accessibility, microphone, and real Groq API behavior.
- Regression tests for every high-priority bug fixed.
- Negative-path tests for permission denial, invalid API key, network failure, target app disappearance, paste fallback, empty recordings, and destructive actions.
- A documented reason when a behavior cannot be tested in XCTest, plus a repeatable manual or script-based QA check.

### Test Categories

Use this hierarchy when adding or reviewing test coverage:

- `FoilTests`: deterministic unit and component tests. These should be the default proof for business logic.
- `FoilUITests`: deterministic UI tests using `--ui-testing` launch modes and controlled app state.
- `tests/test_*.swift`: local integration scripts for behavior that requires real macOS automation, real apps, or real credentials.
- Manual QA checklist: final verification only, not a substitute for automated coverage.

### Required Gates

Before merging each workstream:

```sh
make test
make test-ui
```

Before calling a release candidate ready:

```sh
make test
make test-ui
make qa-local
make test-cleanup-quality
```

`make test-cleanup-quality` may require a local Groq API key. If credentials or permissions are missing, record that explicitly in the release notes or QA log.

### Workstream Evidence Template

Each subagent or implementation workstream must report the same evidence before it is considered ready for review:

- Files changed.
- Tests added or updated.
- Exact commands run.
- Test results, including pass/fail status.
- Skipped tests and the concrete reason they were skipped.
- Manual QA performed, if any.
- Remaining risk or behavior that is not fully covered by automated tests.

### Test Naming And Traceability

New tests should be easy to map back to this plan. Prefer descriptive test names that name the behavior and risk, for example:

- `testAPIKeyMigratesPlaintextFileIntoKeychain`
- `testPasteQueueSerializesConcurrentJobs`
- `testSetupDoesNotReportReadyWhenMicrophonePermissionIsUnknown`

Critical release-readiness regressions may use a `testReleaseReadiness_` prefix when that makes ownership clearer.

### CI And Local QA Policy

CI should stay deterministic. Tests that require real Accessibility permission, real microphone access, real target apps, SkyLight behavior, or live Groq credentials should not silently gate every pull request unless the environment is proven stable.

Use this split:

- CI required: build, deterministic unit tests, deterministic UI tests, request construction, state, persistence, and mocked networking.
- Local required before release candidate: real paste/focus tests via `make test-paste-real` or `make qa-paste`, microphone behavior, signed installed app smoke test, and live Groq cleanup quality checks.
- Manual final check: fresh install, permission prompts, notarized DMG, Homebrew install, and cross-app paste sanity.

Any local-only QA path must have a documented command or checklist entry so it
is repeatable. Record release-candidate evidence in
[`docs/release-qa-log.md`](release-qa-log.md). Skips must fail by default unless
`ALLOW_LOCAL_QA_SKIP=1` is set and the skipped result is explicitly recorded in
that QA log.

### Migration And Rollback Policy

Storage or data model changes must define migration and rollback behavior before implementation:

- API-key migration must handle missing files, unreadable files, invalid empty content, Keychain write failure, and successful cleanup of plaintext files.
- History/audio migration must avoid deleting retryable failed audio unless the user clears/deletes it or a successful retry supersedes it.
- Failed migrations must leave user data recoverable and report an actionable error.
- Downgrade behavior should be considered when changing persisted formats or keys.

### Logging And Privacy Review

Every workstream that touches diagnostics, network requests, paste, history, or setup must verify that logs do not leak sensitive data:

- Do not log API keys.
- Do not log full transcript text by default.
- Avoid logging full file paths when a filename or category is enough.
- Treat target app/window names as potentially sensitive and keep logs concise.
- Error messages shown to users should be actionable without exposing secret values or transcript content.

### XCTest Expectations By Area

Security and persistence:

- API key save/read/delete uses Keychain-backed behavior.
- Legacy plaintext key files migrate successfully and are removed after migration.
- Test storage does not touch the user’s real production key.
- History retention, deletion, clear, retry resolution, and failed-audio cleanup are covered.

Paste and focus:

- `PasteQueue` has a true concurrent XCTest proving FIFO execution without overlap.
- Clipboard restoration honors user changes made during paste delays.
- Paste outcomes distinguish verified success, command-posted/unknown, and clipboard fallback.
- Invalid or terminated targets return fallback outcomes.
- Local integration scripts exercise at least one real async paste path without the UI-test bypass. Use `make test-paste-real` for the installed-app TextEdit smoke path. A local AX-window skip is not a passing release gate unless recorded with `ALLOW_LOCAL_QA_SKIP=1`.

Recording and transcription:

- Recording state transitions are covered for hold mode, toggle mode, cancel, short press, and blocked recording while transcribing.
- Audio format request construction is covered for M4A, WAV, and FLAC.
- Multipart body construction remains covered.
- Transcription cleanup request construction and response parsing are covered.
- Error mapping is covered for invalid API key, file too large, rate limit, server error, malformed response, timeout, offline, and unreachable host.

Onboarding and permissions:

- First-run state does not report ready when required setup is unknown or missing.
- API key save refreshes app setup state.
- Setup check handles missing key, missing Accessibility, denied microphone, and success.
- UI tests cover guided setup states.

History and destructive actions:

- Clear history requires confirmation or an explicit safe flow.
- Row deletion has confirmation or undo coverage if implemented.
- Filter selection is represented as selected state, not disabled-as-selected.
- Search, filter, copy, paste again, retry, delete, and clear remain covered.

Release and docs:

- README claims match actual app behavior and release mechanism.
- Release workflow has a dry-run or documented verification path.
- App icon assets are present and referenced by the Xcode project.

## Workstreams

The plan is organized so subagents can work in parallel with minimal file overlap.

## Wave 1: High-Risk Engineering

### Agent A: API Key Security

Scope:

- `Foil/KeychainHelper.swift`
- `FoilTests/KeychainHelperTests.swift`
- `Foil/ApiKeySetupView.swift`, only if UI copy changes are needed

Tasks:

- Replace plaintext Application Support API-key storage with real macOS Keychain storage.
- Migrate existing plaintext key files into Keychain and remove the plaintext file after successful migration.
- Preserve DEBUG/test isolation.
- Add XCTest coverage for save, read, delete, migration, empty-key rejection, and cleanup.
- Update privacy copy.

Acceptance:

- No Groq API key remains in plaintext app storage after migration.
- Existing users migrate silently.
- Tests pass without touching production Keychain entries.

### Agent B: PasteQueue Serialization

Scope:

- `Foil/PasteQueue.swift`
- `FoilTests/PasteQueueTests.swift`

Tasks:

- Make queued paste jobs actually FIFO serialize across async suspension points.
- Add concurrent XCTest coverage proving handlers do not overlap.
- Preserve invalid-target behavior.
- Define cancellation behavior if needed.

Acceptance:

- Concurrent paste handlers never overlap.
- Regression test fails against the current actor-reentrant implementation and passes after the fix.

### Agent C: Main-Actor Performance Cleanup

Scope:

- `Foil/FoilApp.swift`
- `Foil/AudioRecorder.swift`
- `Foil/TranscriptionService.swift`

Tasks:

- Move audio encoding and multipart body construction off the main actor.
- Keep UI state transitions on `@MainActor`.
- Audit `Task { @MainActor in ... }` blocks for heavy synchronous work.
- Add focused tests for extracted logic where practical.

Acceptance:

- Recording stop does not do large encoding/request-body work synchronously on the main actor.
- Existing app behavior remains unchanged.

### Agent J: Injectable Network Transport

Scope:

- `Foil/TranscriptionService.swift`
- `FoilTests/TranscriptionServiceTests.swift`
- `FoilTests/IntegrationTests.swift`

Tasks:

- Inject a transport/session abstraction instead of hard-wired `URLSession.shared`.
- Add deterministic XCTest coverage for 200, 401, 413, 429, 500, malformed response, timeout, offline, and unreachable host.
- Improve user-facing error mapping for rate limits and quota exhaustion.
- Keep live Groq integration tests optional.

Acceptance:

- API behavior is testable without real Groq credentials.
- User-facing errors are specific and actionable.

## Wave 2: Paste Reliability And Core UX

### Agent D: Paste Verification And Clipboard Safety

Scope:

- `Foil/TextInserter.swift`
- `Foil/BackgroundPaste.swift`
- `Foil/PasteDelivery.swift`
- paste-related tests

Tasks:

- Add pasteboard `changeCount` guards so user clipboard changes are not blindly overwritten.
- Distinguish verified success, command-posted/unknown, and fallback outcomes.
- Verify AX insertion where readable.
- Update UI copy to avoid overclaiming unverified paste success.

Acceptance:

- Clipboard race behavior is covered by tests.
- UI does not claim strong success for unverified event-posting paths.

### Agent F: First-Run Setup Flow

Scope:

- `Foil/FoilApp.swift`
- `Foil/AppState.swift`
- `Foil/MenuBarView.swift`
- `Foil/ApiKeySetupView.swift`

Tasks:

- Treat unknown required setup state as not fully ready on first run.
- Add a guided setup progression for API key, Accessibility, Microphone, and test recording.
- Auto-surface setup on first launch when required state is missing.
- Refresh app state immediately after API key save.
- Avoid repeat nagging after setup is complete.

Acceptance:

- First-run users can complete setup without hunting through settings.
- UI tests cover missing setup states and successful setup progression.

### Agent H: History UX Safety

Scope:

- `Foil/HistoryPopoverView.swift`
- `Foil/SettingsView.swift`
- `Foil/MenuBarView.swift`

Tasks:

- Add confirmation for clear history.
- Add confirmation or undo for row delete if practical.
- Replace disabled filter buttons with a selected-state control.
- Clarify retention and failed-audio persistence.
- Decide whether history remains a window or becomes a true popover.

Acceptance:

- Destructive actions are hard to trigger accidentally.
- Filter selection is semantically accessible.
- Privacy copy matches actual behavior.

### Agent K: App Icon And Assets

Scope:

- `Foil/Assets.xcassets/AppIcon.appiconset`
- Xcode asset references

Tasks:

- Add complete macOS app icon sizes.
- Verify app icon appears in Finder, Dock, menu bar where applicable, and DMG.
- Keep source asset if available.

Acceptance:

- `AppIcon.appiconset` is no longer empty.
- Built app displays the intended icon.

## Wave 3: Integration, Accessibility, And Release Polish

### Agent E: Real Paste Integration Test Path

Scope:

- `Foil/FoilApp.swift`
- `tests/test_*.swift`
- `Makefile`
- CI only if safe

Tasks:

- Add a non-bypassed local test mode that exercises `TextInserter.insertAsync`.
- Keep normal UI tests deterministic.
- Add a `make test-paste-real` or `make qa-paste` target.
- Document required Accessibility permission and local state.

Acceptance:

- At least one repeatable local test exercises real AX/SkyLight/focus behavior.
- Default CI remains stable.

### Agent G: Recording Controls And Accessibility

Scope:

- `Foil/MenuBarView.swift`
- `Foil/AppState.swift`
- `Foil/HotkeyMonitor.swift`, only if callbacks are needed
- UI tests

Tasks:

- Add explicit UI controls for Start, Stop, and Cancel where practical.
- Ensure controls are keyboard reachable.
- Add clear accessibility labels and hints.
- Make toggle mode and hold mode understandable in the session strip.

Acceptance:

- A user can control recording without relying exclusively on holding a modifier key.
- VoiceOver labels describe state and available actions.

### Agent I: Floating Status Polish

Scope:

- `Foil/FloatingStatusView.swift`
- floating panel code in `Foil/FoilApp.swift`

Tasks:

- Review nonactivating panel behavior with keyboard and VoiceOver.
- Make dismiss affordance reliable.
- Ensure long text truncates cleanly.
- Add UI tests or a manual QA checklist for recording, transcribing, success, and error states.

Acceptance:

- Floating status does not hide important information from assistive tech.
- Visual state remains clean across long app names and errors.

### Agent L: Release Workflow Verification

Scope:

- `.github/workflows/deploy.yml`
- `.github/scripts/*`
- `package.json`
- `Makefile`
- README release docs

Tasks:

- Verify the manual tag-driven release workflow.
- Confirm release-prep changes go through PR and merge queue before tagging.
- Verify DMG build, signing, notarization, and GitHub upload.
- Verify Homebrew cask/tap update path.
- Add a dry-run release checklist.

Acceptance:

- A maintainer can cut a signed/notarized release from documented steps.
- README install claims match reality.

Current local verification notes:

- Semantic-release is deprecated for this repo because branch rules require pull requests, merge queue, and `CI Gate`; release automation must not push generated commits directly to `main`.
- `scripts/prepare-release.sh` updates app version/build metadata, `package.json`, `package-lock.json`, and `CHANGELOG.md` for a release-prep PR.
- `.github/workflows/deploy.yml` is manually dispatched with a version input and checks out `v${version}`. It does not run on every `main` push.
- The release workflow creates the GitHub Release if it does not already exist, imports the Developer ID certificate, archives with `MARKETING_VERSION` set to the release version, exports with `ExportOptions.plist`, verifies bundle version/build, creates a DMG, signs it, notarizes it with App Store Connect API-key credentials, staples it, validates Gatekeeper/stapler status, and uploads `Foil-${VERSION}-macos.dmg` plus checksum to the GitHub release.
- Homebrew is verified for the current public beta evidence in `docs/release-qa-log.md`: public tap repository `mean-weasel/homebrew-foil` points at the uploaded `v1.12.2` DMG, the cask SHA-256 matches the release asset digest, and a clean temp-dir cask install/signature smoke passed through tap alias `mean-weasel/foil`. Re-verify this path for each new release.

Release dry-run checklist:

1. Draft release notes in a Markdown file.
2. Prepare the release PR:
   `make prepare-release VERSION=1.12.2 BUILD=34 NOTES=/path/to/release-notes.md`
3. Confirm working tree contains only intentional release-prep changes:
   `git status --short`
4. Review `CHANGELOG.md`, `package.json`, `package-lock.json`, and `Foil.xcodeproj/project.pbxproj`.
5. Open the release-prep PR and merge it through the merge queue after CI is green.
6. Tag the merged `main` commit:
   `git tag v1.12.2 && git push origin v1.12.2`
7. Confirm required repository secrets exist:
   `DEVELOPER_ID_CERT_BASE64`, `DEVELOPER_ID_CERT_PASSWORD`, `APPLE_TEAM_ID`, `APP_STORE_CONNECT_KEY_ID`, `APP_STORE_CONNECT_ISSUER_ID`, `APP_STORE_CONNECT_PRIVATE_KEY`.
8. Confirm the release runner image has the configured Xcode path from `deploy.yml` or update the workflow before release.
9. Run the `Release` workflow manually with the version number without the leading `v` and the release build number.
10. After the workflow completes, download the release DMG and verify locally:
   `spctl -a -vv -t open --context context:primary-signature Foil-VERSION-macos.dmg`
11. Mount the DMG, copy the app to Applications, launch it, and complete a fresh setup smoke test for Accessibility, Microphone, API key, and one transcription.
12. For the public stranger-path smoke, use `docs/fresh-machine-homebrew-onboarding-smoke.md` on a disposable macOS user, VM, spare Mac, or freshly erased machine.

Homebrew/DMG verification path:

1. Confirm the release contains `Foil-VERSION-macos.dmg`.
2. Confirm the release asset digest or `Foil-VERSION-macos.dmg.sha256`, then download the DMG and compute its checksum:
   `shasum -a 256 Foil-VERSION-macos.dmg`
3. Verify the computed checksum matches the GitHub release asset digest or `Foil-VERSION-macos.dmg.sha256`.
4. Update the Homebrew tap cask URL to the exact release asset and the cask `sha256` to the computed value.
5. Verify from a clean tap state:
   `brew untap mean-weasel/foil || true`
6. Tap and install into a temporary app directory before touching `/Applications`:
   `brew tap mean-weasel/foil https://github.com/mean-weasel/homebrew-foil`
   `brew install --cask --appdir=/tmp/foil-brew-apps mean-weasel/foil/foil`
7. Confirm the temp-installed `Foil.app` reports the expected version/build, Gatekeeper accepts it, and deep strict codesign verification passes.
8. Record the workflow run URL, release URL, DMG checksum, cask commit, and local verification result in the release notes or QA log.

### Agent M: README And Docs Cleanup

Scope:

- `README.md`
- user-facing docs

Tasks:

- Remove demo GIF TODO or add a real demo.
- Update setup instructions to match current UI.
- Clarify privacy: Keychain storage, local history, failed audio retention.
- Document required permissions and troubleshooting.
- Document beta caveats around async paste if still imperfect.

Acceptance:

- README no longer overclaims.
- A new user can install, configure, and troubleshoot from docs.

## Final Hardening Gate

Before public release, verify:

- Keychain storage is implemented and plaintext API-key migration has been tested.
- No API keys, full transcripts, or sensitive user data are emitted in normal diagnostics.
- App icon assets are present and visible in a built app.
- README install/setup/privacy claims match actual behavior.
- Release workflow has produced or dry-run-verified a signed and notarized DMG.
- Homebrew install path is verified or README claims are adjusted.
- First-run setup is tested from a clean user state.
- Paste failure states are honest and do not overclaim success.
- There are no known P0/P1 bugs.
- Full QA gate results are recorded with skipped checks explained.
- `docs/release-qa-log.md` is filled in for the release candidate.
- Fresh install on a clean macOS user account.
- No existing Groq key.
- Accessibility denied, then granted.
- Microphone denied, then granted.
- Invalid API key.
- Offline network.
- Long recording.
- Async paste into Notes, TextEdit, Terminal, and browser text field.
- Clipboard preservation during paste.
- History retry and clear.
- Signed/notarized DMG install.
- Homebrew install path.

## Priority Order

1. Keychain storage.
2. PasteQueue serialization.
3. Paste verification and clipboard race protection.
4. Main-actor blocking cleanup.
5. First-run onboarding and permission correctness.
6. Network transport tests and better API errors.
7. App icon and release verification.
8. History destructive confirmations.
9. Recording UI controls and accessibility.
10. README, docs, and demo polish.
