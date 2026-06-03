# T008 Release Smoke Hook And PR Path

Claim:
The next PR should include a small bundled What's New tab and an opt-in installed-app OpenAI smoke path before the next notarized QA artifact is cut.

Decision:
Add the release-safe installed-app OpenAI smoke hook now. The prior evidence showed the only deterministic installed-app cloud smoke path was DEBUG-only, so a fresh notarized artifact would still require manual/keychain/UI proof. The hook is gated by `--e2e-transcribe` and, in non-Debug builds, `E2E_ALLOW_RELEASE_APP_SMOKE=1`; ordinary app launches continue to read provider keys from Keychain.

Strongest realistic failure mode:
The hook accidentally remains DEBUG-only or does not compile in Release.

Evidence:
`xcodebuild build -scheme Foil -configuration Release -destination 'platform=macOS' -derivedDataPath /tmp/foil-release-smoke-derived-data` passed. The build log compiled `E2EAudioStub.swift`, `FoilApp.swift`, `TranscriptionController.swift`, `UITestingController.swift`, and `ReleaseNotes.swift` into the Release app product.

Strongest realistic failure mode:
The installed-app smoke path works only on paper, leaks secrets, or cannot transcribe through OpenAI cloud.

Evidence:
`APP_PATH=/tmp/foil-release-smoke-derived-data/Build/Products/Release/Foil.app make test-live-openai-installed` passed twice with `status=pass` and transcript `The quick brown fox jumps over the lazy dog.` The script sources `.env.local` when needed but only passes the key via environment and does not echo the key value.

Strongest realistic failure mode:
The smoke script mutates tracked fixtures, making repeated local/CI runs flaky.

Evidence:
The first Release smoke exposed that the app deletes successful audio files, which removed tracked `Foil/e2e-test-audio.wav`. The script now copies the input WAV to a temp file before launch. A repeat smoke passed, then `ls -l Foil/e2e-test-audio.wav` showed the fixture still present and `git status --short Foil/e2e-test-audio.wav` showed no deletion.

Strongest realistic failure mode:
The release hook weakens normal production safety by letting Release builds read API keys from environment too broadly.

Evidence:
Focused unit tests passed:
`xcodebuild test -scheme Foil -configuration Debug -destination 'platform=macOS' -only-testing:FoilTests/SingleInstanceGuardTests/testReleaseE2ETranscriptionSmokeRequiresExplicitGate -only-testing:FoilTests/SingleInstanceGuardTests/testE2ETranscriptionSmokeBypassesSingleInstanceGuardWhenGateAllows`.
The implementation only reads `E2E_API_KEY` when `AppDelegate.isE2ETranscriptionSmokeProcess()` is true; in non-Debug builds that also requires `E2E_ALLOW_RELEASE_APP_SMOKE=1`.

Strongest realistic failure mode:
The What's New surface exists in code but not in UI, or the broader suite regresses.

Evidence:
`xcodebuild test -scheme Foil -configuration Debug -destination 'platform=macOS' -only-testing:FoilUITests/FoilUITests/testSettingsWhatsNewShowsOpenAIReleaseNote` passed.
`make build-warnings-as-errors` passed.
`make test` passed.
`git diff --check` passed.

Strongest realistic failure mode:
The older live OpenAI E2E target regressed while the new installed-app path passed.

Evidence:
`set -a; source .env.local; set +a; make test-live-openai` passed with OpenAI response status 200 and transcript `The quick brown fox jumps over the lazy dog.`

PR path:
Opened ready-for-review PR [#212](https://github.com/mean-weasel/foil/pull/212) from `codex/openai-release-whats-new` to `main`. Do not tag or publish a public release from this branch. After merge, cut a fresh Notarized QA Build from the merged commit and install/smoke that notarized artifact before considering the goal complete.

Residual risk / follow-up:
The local Release smoke proves the hook in a Release app product, but not in a notarized DMG containing these changes. Final release proof still requires merge, fresh notarized QA artifact, install from that artifact, Gatekeeper/codesign/stapler/version checks, and `make test-live-openai-installed` pointed at the installed notarized app.
