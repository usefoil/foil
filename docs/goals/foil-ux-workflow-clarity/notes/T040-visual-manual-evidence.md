# T040 Visual And Manual Evidence

## Scope

This note records tranche 1 evidence for the first-run setup path, daily menu/HUD workflow, paste confidence, history recovery, and the repeated test-start permission prompts reported during verification.

## Verification Evidence

- `make build` passed after the tranche 1 changes.
- `make test` passed after the tranche 1 changes.
- `make test-ui` passed after the tranche 1 changes.
- Final UI test result: `** TEST SUCCEEDED **` at `/Users/neonwatty/Library/Developer/Xcode/DerivedData/Foil-acpmtxxdtdquksghmlwalcmkckzy/Logs/Test/Test-Foil-2026.05.16_13-46-47--0700.xcresult`.
- Final unit test result: `** TEST SUCCEEDED **` at `/Users/neonwatty/Library/Developer/Xcode/DerivedData/Foil-acpmtxxdtdquksghmlwalcmkckzy/Logs/Test/Test-Foil-2026.05.16_13-46-38--0700.xcresult`.

## Manual/Demo Notes

- Onboarding: code review confirms `OnboardingView` now exposes setup actions for Add Key, Accessibility settings/check, microphone request/check, and a setup re-check path wired through `FoilApp`. The final step now presents contextual next actions instead of only a disabled completion button. The payoff copy explains hold hotkey, speak, release/stop, and paste into the target app.
- Menu ready/setup states: UI tests launch the real app with seeded states and assert ready, setup-check, setup-failure, and unknown setup behavior. The default menu now centers a workflow status strip and only surfaces setup recovery when relevant.
- Menu recording/transcription/delivery states: UI tests exercise simulated recording and async paste flows, including current-app paste and background paste modes. The menu preserves target feedback such as `Target: Foil UI Test` and exposes `Paste Again` for follow-up action.
- Floating HUD: UI tests cover the floating status toggle, disabled-by-default behavior, and auto-hide after a simulated successful recording. HUD/menu language is generated through `AppState` so status wording stays aligned.
- History/recovery: UI tests exercise seeded history search, failed-record filtering, delete/clear, detail editing, `Copy Export`, `Copy Transcript`, and `Paste Again`. Unit tests cover retryability with and without retained audio and no-audio feedback.
- Permission prompt regression: the repeated microphone prompt is addressed by the `--ui-testing` guard in `requestMicrophoneAccessIfNeeded()`. The repeated Keychain prompt is addressed by the `--ui-testing` API-key guard in `AppState.hasApiKey` and `refreshApiKeyState()`, so UI tests trust seeded test state instead of touching the real login keychain.

## Remaining Visual Gaps

- A first-run onboarding screenshot was not captured during this PM-only task. Onboarding evidence is source-level plus build/test verification, while interactive screenshot coverage remains a good candidate for tranche 3 native QA polish.
- Broad visual distinctiveness is intentionally deferred to tranche 2. The current tranche only made visual changes needed for workflow clarity.
- Native macOS keyboard, VoiceOver, dynamic text, and Light/Dark mode polish are intentionally deferred to tranche 3.
