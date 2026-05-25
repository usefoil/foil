# T002 Judge Receipt

## Decision

Use one coherent implementation slice that separates live Groq XCTest methods into their own class, then makes all default local and CI test invocations explicitly exclude that class. Add a named live target for intentional provider verification.

This is safer than maintaining a skip list of individual live methods because future live Groq test additions can go in the dedicated class and stay outside default test paths.

## Worker Objective

Implement the deterministic/live split:

- Keep deterministic multipart/app-state tests in `IntegrationTests`.
- Move the four real Groq API methods into `LiveGroqIntegrationTests` in the same Swift source file.
- Add Makefile defaults that skip `GroqTalkTests/LiveGroqIntegrationTests` even if the shell exports stale live-test env vars.
- Add `make test-live-groq` for intentional unit-level live Groq API verification.
- Update PR/merge-group CI to skip `LiveGroqIntegrationTests`.
- Update the existing live Groq API workflow to use the explicit target.
- Document the split in local setup, provider QA, and release QA notes.

## allowed_files

- `Makefile`
- `.github/workflows/ci.yml`
- `.github/workflows/e2e.yml`
- `GroqTalkTests/IntegrationTests.swift`
- `README.md`
- `docs/provider-qa-xcuitest.md`
- `docs/release-qa-log.md`
- `docs/goals/live-groq-test-opt-in/state.yaml`
- `docs/goals/live-groq-test-opt-in/notes/*`

## verify commands

- `GROQ_API_KEY=stale RUN_LIVE_GROQ_TESTS=1 make test`
- `GROQ_API_KEY=stale RUN_LIVE_GROQ_TESTS=1 xcodebuild test -scheme GroqTalk -configuration Debug -destination 'platform=macOS' -only-testing:GroqTalkTests -skip-testing:GroqTalkTests/LiveGroqIntegrationTests`
- `make -n test-live-groq`
- `rg -n "LiveGroqIntegrationTests|test-live-groq|RUN_LIVE_GROQ_TESTS" Makefile .github/workflows README.md docs/provider-qa-xcuitest.md docs/release-qa-log.md GroqTalkTests/IntegrationTests.swift`

## stop_if

- The default test path still executes `LiveGroqIntegrationTests`.
- The live Groq path requires printing or exposing a secret.
- Xcode cannot compile the split class without edits outside allowed files.
