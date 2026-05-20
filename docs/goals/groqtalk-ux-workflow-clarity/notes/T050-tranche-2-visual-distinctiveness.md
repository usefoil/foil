# T050 Tranche 2 Plan: Visual Distinctiveness

## Outcome

GroqTalk should look and feel like a focused voice-to-paste utility, not a generic settings panel. The visual system should communicate speed, capture, transcription, cleanup, target delivery, and fallback without adding a marketing page, broad asset overhaul, or decorative clutter.

## Proposed Worker Slices

### V1: Reusable Voice Status Surface

Scope:
- Create one reusable SwiftUI surface for the menu session strip and floating HUD.
- Keep the compact menu/HUD variants distinct, but drive them from the same status model and icon/status mapping.
- Candidate files: `GroqTalk/MenuBarView.swift`, `GroqTalk/FloatingStatusView.swift`, `GroqTalk/AppState.swift`, focused tests in `GroqTalkTests/AppStateTests.swift` and `GroqTalkUITests/GroqTalkUITests.swift`.

Acceptance criteria:
- Ready, recording, transcribing, cleaning, delivered, fallback, setup-needed, and error states share the same status title, icon concept, and semantic color intent across menu and HUD.
- Menu layout remains scannable at current popover size.
- HUD remains compact and does not occlude the active app more than today.
- Reduced-motion users do not receive pulsing or animated recording/transcribing effects.
- `make build`, `make test`, and relevant UI tests pass.

### V2: GroqTalk Visual Signature

Scope:
- Define a small signature built from native materials, one brand accent, waveform/progress cues, and paste-target confirmation.
- Avoid external images unless explicitly approved.
- Candidate files: `GroqTalk/DesignSystem.swift` if introduced, `GroqTalk/MenuBarView.swift`, `GroqTalk/OnboardingView.swift`, `GroqTalk/ApiKeySetupView.swift`, `GroqTalk/FloatingStatusView.swift`.

Acceptance criteria:
- A single brand accent is used for idle/ready and non-alert UI; semantic system colors remain for warnings, errors, and success.
- The palette does not collapse into a one-hue theme and remains legible in Light and Dark mode.
- At least one workflow-specific motif appears in onboarding or setup, such as waveform, hotkey-to-transcript progression, or target paste preview.
- No cards-inside-cards are introduced.
- Text remains within fixed popover/HUD bounds on standard and larger accessibility text settings.
- Screenshots or visual notes are captured before and after implementation.

### V3: Icon And State Language Standardization

Scope:
- Standardize icon choices for API key, microphone, Accessibility, transcription, cleanup, paste, fallback, retry, history, and settings.
- Prefer SF Symbols already available to SwiftUI.
- Candidate files: `GroqTalk/MenuBarView.swift`, `GroqTalk/HistoryPopoverView.swift`, `GroqTalk/OnboardingView.swift`, `GroqTalk/SettingsView.swift`, `GroqTalk/ApiKeySetupView.swift`.

Acceptance criteria:
- Each major workflow concept has one consistent icon family and label across touched surfaces.
- Icons are not the only carrier of meaning; labels or accessibility labels remain clear.
- Error/fallback/retry states are visually distinct without relying on color alone.
- Updated UI tests continue to locate primary controls by stable labels.

### V4: Lightweight Motion Pass

Scope:
- Add limited, native-feeling motion only where it reinforces workflow state.
- Candidate states: recording, transcribing, success/delivered, fallback/needs attention.
- Candidate files: `GroqTalk/FloatingStatusView.swift`, `GroqTalk/MenuBarView.swift`, any reusable status surface introduced by V1.

Acceptance criteria:
- Recording/transcribing motion is subtle, non-looping where possible, or reduced to static changes when Reduce Motion is enabled.
- Success/fallback feedback settles quickly and does not delay user action.
- UI tests remain stable, with animations disabled or not timing-sensitive under `--ui-testing`.

## Verification Plan

- Run `make build`.
- Run `make test`.
- Run `make test-ui` for changed labels, status surfaces, onboarding/setup, HUD, or history actions.
- Capture screenshots or concise visual notes for menu ready, recording/transcribing, delivered/fallback, setup-needed/error, onboarding, and HUD.
- Review Light and Dark mode manually for all touched surfaces.

## Deferred Or Out Of Scope

- New app icon, marketing art, or full brand identity.
- Custom illustration packs.
- Changing the core LSUIElement menu-bar model.
- Reframing background paste as guaranteed delivery.
