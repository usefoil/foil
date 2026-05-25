# T003 Worker Receipt

## Changes

- Split live Groq API XCTest methods into `LiveGroqIntegrationTests` while leaving deterministic multipart/app-state tests in `IntegrationTests`.
- Added `LIVE_GROQ_TEST_CLASS` and `DEFAULT_UNIT_TEST_FILTERS` in `Makefile`.
- Updated `make test` and `make qa` to force `RUN_LIVE_GROQ_TESTS=0` and skip `FoilTests/LiveGroqIntegrationTests`.
- Added explicit `make test-live-groq` for unit-level live Groq API verification.
- Hardened `make test-live-groq` to:
  - require a shell `GROQ_API_KEY`,
  - set `launchctl` user-session env so XCTest receives the intended key,
  - restore previous `launchctl` live Groq env after the run,
  - avoid printing the key.
- Updated PR/merge-group CI unit tests to set `RUN_LIVE_GROQ_TESTS=0` and skip `FoilTests/LiveGroqIntegrationTests`.
- Updated the live Groq API workflow to call `make test-live-groq`.
- Documented deterministic default tests and opt-in live Groq XCTest usage in README, provider QA docs, and release QA notes.

## Verification

- `GROQ_API_KEY=stale RUN_LIVE_GROQ_TESTS=1 make test`
  - PASS
  - `** TEST SUCCEEDED **`
  - xcresult: `Test-Foil-2026.05.24_17-25-06--0700.xcresult`
- `GROQ_API_KEY=stale RUN_LIVE_GROQ_TESTS=1 xcodebuild test -scheme Foil -configuration Debug -destination 'platform=macOS' -only-testing:FoilTests -skip-testing:FoilTests/LiveGroqIntegrationTests`
  - PASS
  - `** TEST SUCCEEDED **`
  - Executed 454 deterministic tests with 0 failures.
- `make -n test-live-groq`
  - PASS
  - Expands to only `FoilTests/LiveGroqIntegrationTests` after the explicit env setup/restore wrapper.
- `GROQ_API_KEY= make test-live-groq`
  - PASS for fail-fast behavior
  - Exited before Xcode with `ERROR: GROQ_API_KEY is required for make test-live-groq`.
- `rg -n "LiveGroqIntegrationTests|test-live-groq|RUN_LIVE_GROQ_TESTS" Makefile .github/workflows README.md docs/provider-qa-xcuitest.md docs/release-qa-log.md FoilTests/IntegrationTests.swift`
  - PASS
  - References show default skips, explicit live target, CI skip, live workflow target, and docs.
- `git diff --check`
  - PASS

## Notes

An attempted pre-hardening `GROQ_API_KEY= make test-live-groq` exposed that Xcode test hosts can still inherit stale `launchctl` user-session env. The final Makefile wrapper now intentionally owns and restores the launchctl live Groq env for the explicit live target.
