# T001 Scout Receipt

## Current Live Groq Test Surfaces

- `FoilTests/IntegrationTests.swift:5-7` declares the class as real Groq Whisper API E2E coverage and says it is skipped unless `RUN_LIVE_GROQ_TESTS=1` and `GROQ_API_KEY` are set.
- `FoilTests/IntegrationTests.swift:25-34` gates live tests with `requireApiKey()`. The gate skips when `RUN_LIVE_GROQ_TESTS != 1` or `GROQ_API_KEY` is empty, but returns any non-empty key when both env vars are present.
- `FoilTests/IntegrationTests.swift:62-135` contains four live API tests. With `RUN_LIVE_GROQ_TESTS=1` and a stale non-empty `GROQ_API_KEY`, these tests call Groq and can fail the default test target.
- `FoilTests/IntegrationTests.swift:139-252` also contains deterministic multipart and app-state tests in the same XCTest class, so excluding the whole class from default tests would currently drop useful non-live coverage.

## Current Default Commands

- `Makefile:99-104` defines `make test` as `xcodebuild test ... -only-testing:FoilTests`. That includes `IntegrationTests`; live methods skip by default, but run if the caller's shell exports `RUN_LIVE_GROQ_TESTS=1`.
- `Makefile:180-185` makes `qa-ci` call `make test`, so it inherits the same behavior.
- `Makefile:199-201` defines `make qa` as an unfiltered `xcodebuild test` invocation. That can run unit and UI tests, and it also inherits live Groq env leakage risk.
- `Makefile:140-144` already has explicit live provider/UI and live CLI transcription targets, but there is no explicit `make test-live-groq` target for the unit-test `IntegrationTests` live API methods.

## CI Behavior

- `.github/workflows/ci.yml:94-105` runs `xcodebuild test ... -only-testing:FoilTests`, so PR and merge-group unit CI has the same env-leakage exposure as `make test` if the runner environment has live Groq opt-in variables.
- `.github/workflows/ci.yml:243-270` focused UI smoke uses explicit `-only-testing` UI cases and does not include the live Groq XCUITest.
- `.github/workflows/e2e.yml:28-47` is already a separate live Groq API workflow. It explicitly sets `RUN_LIVE_GROQ_TESTS=1` and `GROQ_API_KEY` and runs `-only-testing:FoilTests/IntegrationTests`.
- `.github/workflows/macos-e2e-local.yml:72-161` is also live and intentionally requires the Groq secret for the self-hosted local E2E workflow.

## Documentation

- `README.md:73-80` lists `make test` in the local setup path without explaining that live Groq provider tests are separate.
- `docs/provider-qa-xcuitest.md:37-60` documents `make test-provider-qa-live`, but there is no doc entry for live unit-level Groq API format tests.
- `docs/release-qa-log.md` records release gates and live cleanup quality, but not the deterministic/live Groq XCTest split.

## Risk Assessment

Default test determinism is not fully protected by XCTest skip logic alone. The skip gate works when `RUN_LIVE_GROQ_TESTS` is absent, but a stale shell with `RUN_LIVE_GROQ_TESTS=1` and a stale non-empty `GROQ_API_KEY` can cause `make test` and PR/merge-group unit CI to make live Groq API calls and fail on credentials.

## Recommended Implementation Shape

- Move the four live Groq API methods into a dedicated `LiveGroqIntegrationTests` XCTest class/file, leaving deterministic multipart and app-state tests in `IntegrationTests`.
- Add a Makefile variable for the live test class and make default test commands explicitly skip that class.
- Add `make test-live-groq` that sets `RUN_LIVE_GROQ_TESTS=1` and runs only `FoilTests/LiveGroqIntegrationTests`.
- Update CI unit tests to skip `FoilTests/LiveGroqIntegrationTests` even if runner env vars leak.
- Update the existing live Groq API workflow to call the explicit Makefile target or the new class name.
- Document the split in README/provider QA/release QA notes without printing secrets.
