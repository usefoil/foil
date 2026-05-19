# GroqTalk UX Reorganization Design

Status: Draft for review
Date: 2026-05-19

## Context

GroqTalk's menu bar popover, setup status, and Settings window all expose too many decisions at once. The crowded layout makes first-run setup brittle and makes the app look like it is still missing permissions even after macOS has the permission enabled.

The approved direction is a hybrid of:

- a lean menu bar control center for day-to-day recording;
- a guided setup hub for first run and permission repair;
- a reorganized Settings window for durable preferences.

This design is intentionally scoped so GoalBuddy Prep can turn it into granular, measurable implementation tasks.

## Goals

- Make the normal menu bar state feel operational, not like a setup checklist.
- Make setup order obvious, especially Accessibility, Microphone, and API key readiness.
- Keep durable preferences in Settings instead of duplicating them in the menu bar.
- Preserve all existing functionality and state; reorganize rather than invent new preferences.
- Leave enough test and visual verification coverage to catch regressions in permission state, menu density, and settings reachability.

## Non-goals

- No provider, transcription, or paste behavior changes beyond moving controls.
- No visual rebrand.
- No new preference schema unless an existing state cannot support the reorganization.
- No attempt to grant macOS Accessibility or Microphone permissions silently.
- No XCUITest expansion unless explicitly approved for that phase.

## Product Design

### 1. Menu Bar Control Center

The menu bar popover should optimize for the common ready state.

Target layout:

- Header toolbar: Settings, History, Help, Quit.
- Session hero: current state, concise status detail, one primary action.
- Record controls: record/stop and mode-relevant secondary action.
- Last result: one compact row, with History as the escape hatch for detail.
- Setup summary: hidden when ready; visible only when attention is needed.
- Utility footer: app version/status affordances and secondary links.

Durable preferences should move out of the menu bar by default:

- recording shortcut;
- hold-to-record versus toggle;
- paste and clipboard behavior;
- floating status;
- cleanup mode/model;
- mock transcription and other debug controls.

Acceptance for the ready state:

- The ready popover fits at the intended width without feeling like a checklist.
- The primary next action is visually obvious.
- Setup details do not occupy normal ready-state vertical space.
- Every removed menu control is still reachable in Settings or an appropriate secondary surface.

### 2. Guided Setup Hub

Setup should be an explicit flow with stable, inspectable step states.

Target steps:

- Accessibility permission.
- Microphone permission.
- Groq API key.
- Local setup test.

Each step should show:

- status: Ready, Needs action, Checking, or Error;
- one primary action when action is needed;
- concise supporting text;
- a repair path when macOS state is stale.

Important behavior:

- First-run setup appears before the app intentionally triggers an Accessibility prompt path.
- The API key step includes the real Add API Key action instead of only a link to Settings.
- Accessibility and Microphone setup buttons route through app-level handlers that refresh state after returning from System Settings.
- The setup flow avoids hidden final-only blockers; incomplete state is visible at the step that owns it.
- User-facing repair copy explains stale app identity plainly.
- Developer repair commands such as `make prepare-local-permissions-qa` stay in docs and local developer workflows, not primary user UI.

Acceptance for setup:

- A new user can see the next required action without reading developer docs.
- If permission is already enabled, the app refreshes and reflects that state without requiring an unexplained reinstall.
- If macOS has a stale Accessibility identity, the UI explains removing the old GroqTalk entry and reopening the app.
- Setup can be tested without depending on a final aggregate status only.

### 3. Settings Information Architecture

Settings should become the durable preference home. Use native macOS sectioning and keep each pane focused.

Target panes:

- General: launch at login, notifications, sound effects, floating status, updates.
- Recording: shortcut, custom shortcut, hold/toggle mode, input device, audio format.
- Transcription: provider, credentials, connection test, model, speech language, cleanup mode/model.
- Paste & Clipboard: async paste, keep final text on clipboard, experimental background paste, explanatory notes.
- Privacy & Storage: retention, record counts, retained audio, data folder, destructive storage actions separated from passive information.
- Advanced: mock transcription, private paste diagnostics, developer-only diagnostics when needed.

Acceptance for Settings:

- Provider appears before credentials and connection testing.
- Speech language lives with transcription settings.
- Clipboard persistence lives with paste behavior.
- Destructive storage actions are separated from passive privacy/storage information.
- Debug and experimental controls are not mixed into first-run setup or common recording controls.

## GoalBuddy-Ready Work Packages

These packages are ordered to reduce merge conflicts and make acceptance measurable.

### Package 1: UX Inventory Scout

Type: read-only scout

Purpose: create the implementation map before edits begin.

Scope:

- Inventory current menu bar controls and map each to its target destination.
- Inventory Settings panes and current control ownership.
- Inventory setup/onboarding states and permission refresh paths.
- Identify current tests that assert menu/setup/settings behavior.

Acceptance criteria:

- A control migration table exists.
- Each current control has one target destination: menu, setup, settings, advanced, or removed.
- Existing test files and likely update points are listed.
- No product files are modified.

### Package 2: Setup Flow Correctness

Type: bounded implementation worker

Primary files:

- `GroqTalk/OnboardingView.swift`
- `GroqTalk/ApiKeySetupView.swift`
- `GroqTalk/GroqTalkApp.swift`
- `GroqTalk/AppState.swift`
- focused tests under `GroqTalkTests/`

Acceptance criteria:

- First-run onboarding presents before intentional Accessibility prompt initiation.
- API key setup has an in-flow Add/Save/Test path.
- Accessibility and Microphone actions use app-level refresh/polling paths.
- Each setup step exposes Ready, Needs action, Checking, and Error where applicable.
- Stale Accessibility identity copy is user-facing and does not rely on `make` commands.
- Unit tests cover already-granted permission refresh and stale/unknown states where feasible.

Verification:

- Run focused unit tests for setup/AppState behavior.
- Do not run XCUITests unless the active goal explicitly authorizes them.

### Package 3: Menu Bar Control Center

Type: bounded implementation worker

Primary files:

- `GroqTalk/MenuBarView.swift`
- `GroqTalk/AppState.swift` only if state presentation needs small support changes
- focused menu/AppState tests

Acceptance criteria:

- Ready-state menu shows session hero, primary action, record controls, compact last result, and utility footer.
- Setup details are hidden or collapsed when all setup steps are ready.
- Durable preferences listed in this spec are no longer exposed as normal menu-bar quick controls.
- If setup needs attention, the menu shows a compact summary and route to setup details.
- History, Settings, Help, and Quit remain reachable.
- Existing recording controls still work from the menu bar.

Verification:

- Run focused unit tests for menu presentation state.
- Capture a visual receipt of ready and setup-needed menu states.

### Package 4: Settings Reorganization

Type: bounded implementation worker

Primary files:

- `GroqTalk/SettingsView.swift`
- related view models/helpers if they already own settings sections
- focused settings tests if present

Acceptance criteria:

- Settings panes match the approved IA: General, Recording, Transcription, Paste & Clipboard, Privacy & Storage, Advanced.
- Provider precedes credentials and connection test.
- Speech language moves to Transcription.
- Keep final text on clipboard moves to Paste & Clipboard.
- Privacy & Storage separates retention/status information from destructive actions.
- Advanced/debug controls are visually and semantically separated from user setup.
- Settings content does not clip at the supported window size; scrolling is acceptable for dense panes.

Verification:

- Build the app.
- Capture a visual receipt for each affected Settings pane.

### Package 5: Copy, Repair Guidance, and Docs

Type: bounded implementation worker

Primary files:

- `README.md`
- relevant docs under `docs/`
- user-facing strings in setup/menu views only where needed

Acceptance criteria:

- User-facing setup copy explains stale macOS permission identity without developer command names.
- Developer repair guidance documents local commands separately.
- The docs explain the intended setup order and how to reset local Accessibility state during development.
- No primary app UI tells regular users to run `make prepare-local-permissions-qa`.

Verification:

- Search confirms developer-only commands do not appear in primary user UI.
- Documentation links and command names are accurate.

### Package 6: Regression and Visual Verification

Type: read-only judge or verification worker

Acceptance criteria:

- Full unit test command has been run or a blocker is documented.
- `make test-ui` behavior is verified only if UI testing is authorized for the goal.
- Local permission repair scripts are checked with their non-mutating mode where possible.
- Visual receipts cover menu ready state, menu setup-needed state, onboarding/setup, and representative Settings panes.
- No duplicate running menu bar app remains after test or run scripts complete.

Suggested commands:

- `make test`
- `scripts/prepare-local-permissions-qa.sh --check`
- `make test-ui` only when explicitly authorized
- `./script/build_and_run.sh --verify` when install/run verification is in scope

## Cross-Package Acceptance Criteria

- The ready menu bar UI is clearly less crowded than the current baseline.
- Setup has an obvious next action at every incomplete step.
- Settings is the single home for durable preferences.
- Existing user preferences continue to load with their current values.
- No regular-user UI includes local developer repair commands.
- The implementation receipts identify every moved control and its new location.
- Remaining risks or blocked checks are documented before final closeout.

## Risks

- macOS TCC state cannot be fully automated, so permission refresh needs targeted unit coverage plus manual receipts.
- Menu bar UI tests can launch duplicate app instances if test orchestration is not careful.
- Moving controls can break discoverability unless Settings search/labels are clear.
- Separating setup from settings can create duplicate copy unless each surface has a strict purpose.

## Open Questions for Implementation Planning

- Should Advanced be visible by default or hidden behind a debug/developer flag?
- Should the menu setup summary open a dedicated setup window, a Settings pane, or an inline disclosure?
- Should a single high-frequency preference remain in the menu after user testing, or should the first pass move all durable preferences to Settings?
