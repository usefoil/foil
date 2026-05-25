# T002 Judge Receipt

Result: done

## Decision

Proceed with setup flow correctness as the first Worker slice.

## Rationale

This is the highest-value first slice because it addresses the original setup confusion directly: onboarding does not currently provide an in-flow API key save/test path, permission settings buttons bypass app-level refresh handlers, and setup status is split between onboarding, menu setup rows, and aggregate `AppState.isSetupReady`.

It is also a safe first slice because it can be bounded to setup/onboarding/app-state files and focused unit tests without requiring Settings reorganization or XCUITest.

## Exact Worker Objective

Implement setup flow correctness:

- first-run context before intentional Accessibility prompt initiation;
- in-flow API key Add/Save/Test from onboarding;
- Accessibility and Microphone actions routed through app-level handlers;
- visible per-step setup states;
- stale Accessibility identity copy suitable for regular users, with developer repair commands kept out of primary UI.

## Allowed Files

- `Foil/OnboardingView.swift`
- `Foil/ApiKeySetupView.swift`
- `Foil/FoilApp.swift`
- `Foil/AppState.swift`
- `FoilTests/`

## Verify

- Run focused setup/AppState unit tests selected by the Worker.
- Run the GoalBuddy state checker after updating the Worker receipt.
- Do not run XCUITests unless the user explicitly authorizes that task.

## Stop If

- The implementation needs files outside the allowed set.
- Permission behavior cannot be tested without introducing a larger architectural seam.
- The work needs XCUITest authorization.
- A product-copy decision is required for stale permission identity repair.
