# T001 UX Inventory Scout Receipt

Result: done

## Evidence Read

- `docs/superpowers/specs/2026-05-19-foil-ux-reorganization-design.md`
- `Foil/MenuBarView.swift`
- `Foil/SettingsView.swift`
- `Foil/OnboardingView.swift`
- `Foil/ApiKeySetupView.swift`
- `Foil/AppState.swift`
- `FoilTests/`
- `FoilUITests/`

No implementation files were modified. No XCUITests were run.

## Current Surface Map

### Menu Bar

`MenuBarView` renders these sections unconditionally in the popover body:

- toolbar actions;
- session strip;
- setup panel;
- feedback panel;
- last result section;
- quick controls.

Evidence: `MenuBarView.swift:66-74`.

The session strip already has the intended model shape: title, detail, icon/tone, timer, and primary action. Evidence: `MenuBarView.swift:300-315`, `AppState.swift:437-455`.

The setup panel is always visible and always renders Accessibility, Microphone, API key, and local setup test rows. Evidence: `MenuBarView.swift:138-182`, `MenuBarView.swift:185-215`.

Quick Controls currently mixes immediate recording controls with durable preferences and debug controls. Evidence: `MenuBarView.swift:408-430`, `MenuBarView.swift:470-541`.

### Setup / Onboarding

`OnboardingView` has three steps: API Key, Accessibility, Microphone. Evidence: `OnboardingView.swift:8-10`.

API key onboarding only links to Groq keys and shows a status badge; the real save/test surface is `ApiKeySetupView`. Evidence: `OnboardingView.swift:90-110`, `ApiKeySetupView.swift:17-83`.

Accessibility and Microphone onboarding buttons directly open `NSWorkspace` URLs rather than using the app-level handlers used elsewhere. Evidence: `OnboardingView.swift:131-137`, `OnboardingView.swift:166-172`.

Microphone check is triggered when entering the Microphone step. Evidence: `OnboardingView.swift:81-84`.

`AppState.isSetupReady` is currently a strict aggregate of Accessibility, Microphone, and API key. Evidence: `AppState.swift:332-340`.

`sessionPresentation` already makes setup the idle-state priority and selects a primary action by first missing setup item. Evidence: `AppState.swift:437-445`.

### Settings

Current tabs: General, Recording, Transcription, Paste, Privacy. Evidence: `SettingsView.swift:4-11`, `SettingsView.swift:36-62`.

Settings window is fixed at `520x360`. Evidence: `SettingsView.swift:63-65`.

General currently contains sound effects, floating status, keep-final-text-on-clipboard, launch at login, notifications, and updates. Evidence: `SettingsView.swift:76-115`.

Recording currently contains hotkey, custom key recorder, hold/toggle mode, audio format, language, and input device. Evidence: `SettingsView.swift:119-165`.

Transcription currently shows API key status before provider, then provider, provider-specific fields, connection test, cleanup settings, and debug mock transcription. Evidence: `SettingsView.swift:168-220` plus the remaining transcription form.

Paste currently contains async paste and experimental background paste, but not keep-final-text-on-clipboard. Evidence: `SettingsView.swift:302-315`.

Privacy currently contains retention, local counts, data folder, and destructive history/audio clearing in one section. Evidence: `SettingsView.swift:318-350`.

## Control Migration Table

| Current control/surface | Current location | Target destination | Notes |
| --- | --- | --- | --- |
| Settings | menu toolbar | menu toolbar / utility header | Keep reachable. |
| History | menu toolbar and last result | menu toolbar / compact last result affordance | Keep reachable; avoid duplicate heavy presentation. |
| Help | menu toolbar | menu utility/header | Keep reachable. |
| Retry last failure | menu toolbar | session hero primary action or contextual failure row | Avoid extra toolbar density when session action already handles retry. |
| Quit | menu toolbar | menu utility/header/footer | Keep reachable. |
| Session state/title/detail/action | menu session strip | menu hero | Keep and make it the primary ready-state surface. |
| Accessibility row | always-visible setup panel | setup hub and compact menu summary only when needed | Menu should not show full row in ready state. |
| Microphone row | always-visible setup panel | setup hub and compact menu summary only when needed | Unknown state should support check action. |
| API key row | always-visible setup panel | setup hub and Transcription settings | Onboarding needs real Add/Save/Test path. |
| Local setup test | always-visible setup panel | setup hub / diagnostics summary when needed | Keep testable without crowding ready state. |
| Target feedback | feedback panel | merge into session hero/detail or transient row | Hide when empty and async paste is off. |
| Feedback message | feedback panel | session hero/status detail | Avoid duplicating status. |
| Clipboard feedback | feedback panel | compact transient status or last-result metadata | Keep visible only when relevant. |
| Last Result text | last result section | compact menu row | Use History for details. |
| Copy last result | last result section | compact last-result action | Keep reachable. |
| Paste Again | last result section | compact last-result/session action | Keep reachable. |
| Start/Stop/Cancel recording | Quick Controls | menu record controls | Keep in menu; separate from durable preferences. |
| Hotkey picker/custom recorder | Quick Controls and Recording settings | Recording settings only | Durable preference. |
| Hold/toggle recording mode | Quick Controls and Recording settings | Recording settings only | Durable preference. |
| Async paste | Quick Controls and Paste settings | Paste & Clipboard settings | Durable preference. |
| Keep final text on clipboard | Quick Controls and General settings | Paste & Clipboard settings | Move out of General. |
| Floating status | Quick Controls and General settings | General settings | Durable preference. |
| Cleanup mode | Quick Controls and Transcription settings | Transcription settings | Durable preference. |
| Mock transcription | Quick Controls and Transcription settings under DEBUG | Advanced settings | Debug-only. |
| Sound effects | General settings | General settings | Keep. |
| Launch at login | General settings | General settings | Keep. |
| Notifications | General settings | General settings | Keep. |
| Updates | General settings | General settings | Keep. |
| Audio format | Recording settings | Recording settings | Keep. |
| Language | Recording settings | Transcription settings | Speech-language preference. |
| Input device | Recording settings | Recording settings | Keep. |
| Provider picker | Transcription settings after API key row | Transcription settings before credentials | Reorder. |
| API key status/change | Transcription settings before provider | Transcription settings after provider | Reorder and keep opening `api-key-setup`. |
| Connection test | Transcription settings | Transcription settings after credentials/provider config | Keep. |
| Provider-specific base URL/model | Transcription settings | Transcription settings | Keep with provider. |
| History retention/counts/data folder | Privacy settings | Privacy & Storage settings | Keep. |
| Clear History/Clear Failed Audio | Privacy settings | Privacy & Storage destructive section | Separate from passive info. |
| Experimental background paste | Paste settings | Paste & Clipboard or Advanced, depending final product decision | Spec currently targets Paste & Clipboard with explanations. |

## Test Update Points

Likely unit-test anchors:

- `FoilTests/AppStateTests.swift`: setup readiness, setup check transitions, accessibility recovery copy, session presentation, async paste persistence, mock transcription persistence.
- `FoilTests/RecordingFlowTests.swift`: session presentation and menu bar icon behavior around setup/not-ready states.
- `FoilTests/HotkeyMonitorTests.swift`: hotkey lifecycle, affected only if hotkey control wiring changes.
- `FoilTests/PasteControllerTests.swift`: async paste behavior should remain unchanged after control relocation.

Likely UI-test anchors if explicitly authorized later:

- `FoilUITests/FoilUITests.swift`: setup panel identifiers, setup check action, seeded setup states, mock transcription toggle, async paste toggle, live microphone smoke.

Current UI tests reference menu quick controls and setup rows that the design intends to remove or collapse, so UI tests will need intentional updates before `make test-ui` can be expected to pass.

## Implementation Risks for Judge

- The setup flow should probably be the first Worker slice because it addresses the original permission-order confusion and several existing source gaps are localized to `OnboardingView`, `ApiKeySetupView`, `FoilApp`, `AppState`, and tests.
- Menu simplification can be done before Settings only if every removed preference already has a Settings destination. Keep-final-text-on-clipboard and mock transcription need Settings IA work to avoid hiding them.
- Settings reorganization likely needs an `advanced` tab enum case and probably a label change from Paste/Privacy to Paste & Clipboard/Privacy & Storage.
- XCUITests currently assert menu setup rows and quick controls by identifier, so they should be treated as a later authorized verification/update slice, not a blocker for unit-tested implementation.
