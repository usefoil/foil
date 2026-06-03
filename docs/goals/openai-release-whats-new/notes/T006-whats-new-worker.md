# T006 What's New Worker

Claim: Foil now has a small bundled What's New surface in Settings, and the current OpenAI note is visible without runtime network fetching.

Strongest realistic failure mode: The UI appears in source but is not wired into the app target, does not open to the new tab in UI tests, or requires network/GitHub access when Settings opens.

Evidence:
- Added `Foil/ReleaseNotes.swift` with static bundled release-note data; no network client or GitHub API use is introduced.
- Added a `What's New` case to `SettingsView.Tab`, a native Form pane, and a UI-test launch argument `--settings-tab-whats-new`.
- Added `FoilUITests/FoilUITests/testSettingsWhatsNewShowsOpenAIReleaseNote`.
- First focused UI run failed because the test asserted a Form-level accessibility identifier that SwiftUI did not expose. The failure trace proved the new tab and note text were visible. The assertion was corrected to match the actual accessibility tree.
- Rerun passed:
  - `xcodebuild test -scheme Foil -configuration Debug -destination 'platform=macOS' -only-testing:FoilUITests/FoilUITests/testSettingsWhatsNewShowsOpenAIReleaseNote`
  - Result: `** TEST SUCCEEDED **`
- Warning-clean build passed:
  - `make build-warnings-as-errors`
  - Result: `** BUILD SUCCEEDED **`
- Broad unit test target passed:
  - `make test`
  - Result: `** TEST SUCCEEDED **`
- `git diff --check` passed with no whitespace errors.

Residual risk / follow-up: This implementation is local source only. It has not yet gone through PR/merge queue or a new notarized QA artifact, so the installed `/Applications/Foil.app` does not include the What's New tab yet.
