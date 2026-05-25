# T050 Tranche 3 Plan: Native macOS Polish

## Outcome

Foil should behave like a mature macOS menu bar utility: keyboard-friendly, accessible, predictable, and clear about where settings, history, help, permissions, and paste recovery live.

## Proposed Worker Slices

### M1: App Commands And Menu Reachability

Scope:
- Add or improve native commands for Settings/Preferences, History, Start/Stop/Cancel recording, Help/Troubleshooting, Copy Transcript, Paste Again, and Delete where appropriate.
- Candidate files: `Foil/FoilApp.swift`, `Foil/MenuBarView.swift`, `Foil/HistoryPopoverView.swift`, `Foil/SettingsView.swift`.

Acceptance criteria:
- Standard shortcuts open Settings and History when the app is active.
- Start/Stop/Cancel commands are disabled or unavailable when unsafe.
- Copy/Paste Again commands operate on the current transcript or selected history item where context is unambiguous.
- Help/Troubleshooting opens a native window or existing setup recovery surface.
- Commands have stable labels and accessibility names.

### M2: Settings Architecture And Permission Timing

Scope:
- Clarify embedded quick settings versus full settings.
- Review API key, Accessibility, and microphone permission prompt timing so system prompts happen with user context.
- Candidate files: `Foil/MenuBarView.swift`, `Foil/SettingsView.swift`, `Foil/ApiKeySetupView.swift`, `Foil/OnboardingView.swift`, `Foil/FoilApp.swift`.

Acceptance criteria:
- The menu popover clearly links to full Settings for advanced controls.
- Embedded quick settings do not imply advanced settings are absent.
- Permission prompts are only triggered by explicit setup/check/request actions or well-contextualized first-run paths.
- UI tests continue to avoid real microphone and Keychain prompts under `--ui-testing`.
- Manual QA confirms no repeated permission dialogs at test/app startup.

### M3: Native History Interaction Model

Scope:
- Make history behave more like a native searchable list.
- Candidate files: `Foil/HistoryPopoverView.swift`, `Foil/HistoryStore.swift` if needed, `FoilUITests/FoilUITests.swift`, `FoilTests/HistoryPopoverTests.swift`.

Acceptance criteria:
- Rows support keyboard selection and activation.
- Delete behavior is available through keyboard and context menu where appropriate.
- Search and failed/success filters preserve focus and selection predictably.
- Retry, Paste Again, Copy Transcript, and Copy Export remain explicit and confirmed.
- Empty, filtered-empty, retryable failure, and no-audio states have clear text.

### M4: Keyboard Accessibility For Hotkey Recording

Scope:
- Convert the custom hotkey recorder into a focusable, keyboard-accessible control with explicit active/cancel states.
- Candidate files: `Foil/KeyRecorderView.swift`, `Foil/SettingsView.swift`, focused tests if existing view tests support it.

Acceptance criteria:
- The hotkey recorder can be focused without a pointer.
- Active recording state is announced visually and through accessibility.
- Escape cancels recording without saving.
- Invalid or duplicate shortcuts produce understandable feedback.
- Existing hotkey persistence semantics are preserved.

### M5: Layout, Accessibility, And Mode Audit

Scope:
- Reduce fixed-size clipping risk and verify the touched surfaces in Light/Dark mode, VoiceOver labels, keyboard paths, and larger text.
- Candidate files: `Foil/OnboardingView.swift`, `Foil/ApiKeySetupView.swift`, `Foil/MenuBarView.swift`, `Foil/FloatingStatusView.swift`, `Foil/SettingsView.swift`, `Foil/HistoryPopoverView.swift`.

Acceptance criteria:
- Onboarding, API key setup, menu popover, floating HUD, settings, and history do not clip primary labels or buttons at standard and larger text sizes.
- Color is not the only indicator for selected/error/success/fallback states.
- Primary controls have useful accessibility labels.
- Keyboard paths exist for setup check, Add Key, History, Settings, copy, paste again, retry, and delete.
- Light and Dark mode snapshots/manual notes are captured for every touched surface.

## Verification Plan

- Run `make build`.
- Run `make test`.
- Run `make test-ui` after command, label, history, settings, hotkey, or permission-path changes.
- Perform manual QA for permission prompts, keyboard navigation, VoiceOver labels, Light/Dark mode, larger text, and reduced motion.
- Keep screenshots or concise notes for each touched surface.

## Deferred Or Out Of Scope

- Replacing the menu-bar-only product model.
- Changing API-key storage away from Keychain.
- Adding private paste APIs or promising paste success that cannot be verified.
- Full visual rebrand; tranche 3 is native behavior and accessibility polish.
