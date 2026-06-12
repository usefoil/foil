## [1.13.5](https://github.com/usefoil/foil/compare/v1.13.4...v1.13.5) (2026-06-12)

- Fix Sparkle update signing for release DMGs so in-app updates can validate downloaded updates.
- Add release and QA guards that require Sparkle EdDSA signatures and verify the shipped app embeds `SUPublicEDKey`.


## [1.13.4](https://github.com/mean-weasel/foil/compare/v1.13.3...v1.13.4) (2026-05-31)

- Fixed installed-app automation smoke launches so they no longer get diverted into an already-running Foil process before diagnostics and automation handlers are configured.
- Hardened production cask QA so artifact validation fetches and extracts the release DMG without moving an existing `/Applications/Foil.app`.


## [1.13.3](https://github.com/mean-weasel/foil/compare/v1.13.2...v1.13.3) (2026-05-30)

- Stabilized production queued-paste compatibility smoke runs so installed-app QA fails fast when macOS permission or target-app state blocks automation.
- Added automation-safe Keychain handling and setup refresh guards so smoke runs do not trigger stale production security prompts.
- Expanded smoke diagnostics around frontmost app capture and SecurityAgent interference for clearer release QA evidence.


## [1.13.2](https://github.com/mean-weasel/foil/compare/v1.13.1...v1.13.2) (2026-05-30)

- Added recovery handling for rare macOS Microphone permission prompt timeouts so setup no longer spins indefinitely when TCC has a stale or stuck row.
- Documented stale TCC cleanup steps for production permission QA, including Foil-scoped Microphone reset and TCC cache restart guidance.


## [1.13.1](https://github.com/mean-weasel/foil/compare/v1.13.0...v1.13.1) (2026-05-29)

### Setup permission release proof

- Added production setup-permission smoke tooling for the public Homebrew cask and notarized Developer ID app.
- Added release-gate checks for required commit inclusion, Gatekeeper notarization, deep codesign verification, and `/Applications/Foil.app` process identity.
- Documented the production Accessibility and Microphone evidence template for release QA and issue follow-up.


## [1.13.0](https://github.com/mean-weasel/foil/compare/v1.12.2...v1.13.0) (2026-05-28)

### Experimental queued paste

- Added the experimental queued-paste workflow for collecting multiple transcripts before delivery.
- Added a user-facing queued-paste delivery hotkey, `Control-Shift-V`, with step-through and drain behavior based on queued-paste mode.
- Added settings, diagnostics, and conflict handling for the queued-paste delivery shortcut.
- Expanded queued-paste compatibility smoke coverage for TextEdit, Chrome, Safari, and local browser fallback targets.

### Providers and cleanup

- Added custom OpenAI-compatible chat cleanup provider routing so transcript cleanup can use a selected custom chat endpoint.

### Production and development workflow

- Added a separate `Foil Dev` app flavor with bundle ID `com.neonwatty.Foil.Dev`.
- Isolated dev app preferences, Keychain service, diagnostics, transcription history, app support data, macOS TCC identity, and single-instance behavior from production.
- Added dev build/install/run and permission QA targets, and made the Codex Run action use the dev flavor by default.
- Disabled Sparkle production updates in the dev flavor.

### Install and release documentation

- Clarified Homebrew as the primary production install path and documented current public install status.
- Added fresh-machine onboarding smoke documentation and Homebrew release validation notes.


## [1.12.2](https://github.com/mean-weasel/foil/compare/v1.12.1...v1.12.2) (2026-05-27)

### Visual polish

- Updated the macOS app icon assets with the new Foil abstract cylinder/wave mark.
- Added a Foil-branded drag-to-Applications DMG background for the release installer.

### Release notes

- Documented the branded DMG presentation check in the release process.


## [1.12.1](https://github.com/mean-weasel/foil/compare/v1.12.0...v1.12.1) (2026-05-24)

### Bug Fixes

- Stabilized the full macOS UI diagnostics suite for open-beta readiness.
- Replaced fragile UI-test interaction paths with deterministic app-side command hooks where needed.
- Hardened sequential UI test launches against stale Foil processes.

### Release Infrastructure

- Replaced semantic-release with an intentional manual tag-driven release workflow compatible with PR and merge queue rules.
- Added release-prep tooling and documentation for version, build, changelog, DMG, appcast, and Homebrew release steps.

### Local Models

- Improved Local whisper.cpp setup coverage, persistence checks, and in-app setup guidance.


# [1.12.0](https://github.com/mean-weasel/foil/compare/v1.11.0...v1.12.0) (2026-05-20)


### Bug Fixes

* validate custom providers and skip unsupported cleanup ([451f9c3](https://github.com/mean-weasel/foil/commit/451f9c312292bc5b682a4d27299bcb8600cf8f0f))


### Features

* add OpenAI-compatible transcription provider ([0c72b2e](https://github.com/mean-weasel/foil/commit/0c72b2e5d8aa4f4641751a1606d5fa58a0ff6fc7))
* polish transcription provider setup presets ([#79](https://github.com/mean-weasel/foil/issues/79)) ([78711b9](https://github.com/mean-weasel/foil/commit/78711b9b7154e01b54a4eda9c2009596909d0e6f))

# [1.11.0](https://github.com/mean-weasel/foil/compare/v1.10.2...v1.11.0) (2026-05-14)


### Features

* add E2E transcription UI test with real Groq API ([#73](https://github.com/mean-weasel/foil/issues/73)) ([e6fd900](https://github.com/mean-weasel/foil/commit/e6fd900c91f7110be0408aa2d22f973dae14ae38))
* E2E transcription test infrastructure (stub + controller swap) ([#72](https://github.com/mean-weasel/foil/issues/72)) ([011ecda](https://github.com/mean-weasel/foil/commit/011ecdaa717dd0748bc8d19eca5989c2bea1a4d8)), closes [#if](https://github.com/mean-weasel/foil/issues/if)

## [1.10.2](https://github.com/mean-weasel/foil/compare/v1.10.1...v1.10.2) (2026-05-14)


### Bug Fixes

* suppress accessibility prompt during unit tests ([#70](https://github.com/mean-weasel/foil/issues/70)) ([244331b](https://github.com/mean-weasel/foil/commit/244331b3e76fdadb9db2403122b3ab3d6dfc3ed4))

## [1.10.1](https://github.com/mean-weasel/foil/compare/v1.10.0...v1.10.1) (2026-05-14)


### Bug Fixes

* align retry-transcription test with delegate notification behavior ([#68](https://github.com/mean-weasel/foil/issues/68)) ([e741d30](https://github.com/mean-weasel/foil/commit/e741d30322a30c71844384de65f6e989262a3147))

# [1.10.0](https://github.com/mean-weasel/foil/compare/v1.9.1...v1.10.0) (2026-05-14)


### Features

* prevent multiple app instances from running simultaneously ([#65](https://github.com/mean-weasel/foil/issues/65)) ([58be489](https://github.com/mean-weasel/foil/commit/58be4891dd8ec01e56212f8b01395ca770f37813)), closes [#62](https://github.com/mean-weasel/foil/issues/62) [#63](https://github.com/mean-weasel/foil/issues/63)

## [1.9.1](https://github.com/mean-weasel/foil/compare/v1.9.0...v1.9.1) (2026-05-13)


### Bug Fixes

* use launchctl setenv to pass env vars to xcodebuild test host ([#64](https://github.com/mean-weasel/foil/issues/64)) ([7c4e1e0](https://github.com/mean-weasel/foil/commit/7c4e1e06c00e507565430417ca7a7163f86716b9))


# [1.9.0](https://github.com/mean-weasel/foil/compare/v1.8.2...v1.9.0) (2026-05-13)


### Features

* use stable device UID for persistence and extract appcast script ([#56](https://github.com/mean-weasel/foil/issues/56)) ([f06535f](https://github.com/mean-weasel/foil/commit/f06535fab195c4e040747cff4bda2be24e19ce36))
