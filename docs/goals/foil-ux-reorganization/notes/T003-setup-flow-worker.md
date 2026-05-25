# T003 Worker Receipt

Result: done

## Summary

Implemented the setup flow correctness slice within the allowed files.

Changes:

- First-run onboarding now causes launch to skip the initial hotkey monitor start, avoiding the Accessibility prompt path before setup context.
- Completing onboarding starts the hotkey monitor afterward when not in tests and not already running.
- Onboarding Accessibility and Microphone buttons now route through app-level handlers, so existing refresh/polling is used after opening System Settings.
- The API key onboarding step now exposes an Add API Key action that opens the existing Save & Test setup window.
- Accessibility stale-identity copy is now user-facing in app UI and no longer exposes the local `make prepare-local-permissions-qa` command.
- Focused tests now assert that both regular and debug recovery copy avoid developer commands and explain the stale identity repair path.

## Verification

Passed:

```text
xcodebuild test -scheme Foil -configuration Debug -destination 'platform=macOS' -only-testing:FoilTests/AppStateTests
```

Result:

```text
Executed 105 tests, with 0 failures.
** TEST SUCCEEDED **
```

Additional check:

```text
rg -n "make prepare-local-permissions-qa" Foil FoilTests
```

Result: only negative assertions in `FoilTests/AppStateTests.swift`; no app UI source references.

## Notes

No XCUITests were run. This slice compiles through the focused Xcode test build, but visual onboarding verification remains for the later regression/visual verification task.
