# Foil Marketing Landing Page Improvement Design

## Status

Approved for planning on 2026-06-03.

## Objective

Improve Foil's existing static marketing landing page so a new beta visitor
quickly understands the daily value of the app: hold a key, speak naturally,
release, and get text pasted into the Mac app they were already using.

The page should convert better while adding enough product detail to answer
common trust, provider, privacy, and reliability questions. This is an
improvement to the current `site/` page, not a new site architecture.

## Existing Context

- The landing page lives in `site/index.html` with styling in `site/styles.css`.
- The page is deployed by the `Landing Page` GitHub Pages workflow when `site/**`
  changes.
- Existing public proof assets live in `site/assets/screenshots/` and are real
  Foil app screenshots captured from deterministic UI-testing states.
- The current page already has hero, screenshot, workflow, provider, install,
  and footer sections.
- The repository evidence guide treats website changes as needing local file
  inspection plus browser screenshot evidence when layout changes.

## Audience

Prospective Foil users, beta testers, and maintainers evaluating whether Foil
is useful, trustworthy, and practical enough to install.

## Core Message

Lead with speed everywhere the user types:

> Dictate into any Mac app. Hold a key, speak naturally, release, and Foil
> pastes the transcript where your cursor already is.

Provider choice, privacy posture, and macOS reliability should support this
message immediately after the hero, but should not replace it as the first
viewport promise.

## Page Structure

The improved page should use this order:

1. Header navigation
2. Hero
3. Proof strip
4. Real screenshot proof
5. Feature tour
6. Provider choice
7. Privacy and reliability
8. Install
9. Footer

### Header Navigation

Keep the Foil mark and sticky header. Adjust navigation to match the improved
page:

- Screenshots
- Features
- Providers
- Privacy
- Install
- GitHub

The header should remain compact on desktop and wrap cleanly on mobile.

### Hero

The hero should do more conversion work than the current page.

Required content:

- Brand/product signal: Foil remains prominent.
- Headline: focus on dictating into any Mac app.
- Body copy: explain hold, speak, release, paste in one short paragraph.
- Primary CTA: Install with Homebrew.
- Secondary CTA: View on GitHub.
- Compatibility line: macOS 14+, Apple Silicon and Intel.
- Visual proof: preserve a realistic app preview or real screenshot composition.

The first viewport should leave a hint of the next section visible on typical
desktop and mobile viewports.

### Proof Strip

Add a compact strip below the hero with dense, scannable claims:

- Hold-to-talk
- Release-to-paste workflow
- Cloud or local transcription
- History recovery

The strip should be factual and should not include fake metrics.

### Real Screenshot Proof

Keep real app screenshots prominent and early. The section should continue to
use the verified assets in `site/assets/screenshots/` unless a later
implementation pass captures newer deterministic screenshots.

The section should show:

- Ready control center as the primary screenshot.
- Provider settings, onboarding, and setup-needed states as supporting proof.
- Captions that explain what the screenshots prove without claiming private or
  live-provider behavior that the screenshots do not show.

### Feature Tour

Add a detailed but skimmable feature tour with four groups.

#### Capture

Explain:

- Hold-to-record.
- Toggle mode.
- Hotkey choices.
- Audio formats.
- Language hints.

#### Transcribe

Explain:

- Groq Whisper.
- OpenAI Whisper.
- Local whisper.cpp.
- Custom OpenAI-compatible transcription endpoints.

#### Polish

Explain:

- Optional cleanup and rewrite modes.
- Cleanup provider choice.
- Raw transcript fallback when cleanup fails after transcription succeeds.

#### Paste And Recover

Explain:

- Auto-paste into the active app.
- Clipboard safety.
- History recovery.
- Copy, paste, edit, export, delete, and retry past transcriptions.

Use four feature groups instead of a long checklist. Each group should have a
clear heading, concise explanation, and short bullets.

### Provider Choice

Keep the existing provider section but update it to include all current
transcription provider paths:

- Groq Whisper
- OpenAI Whisper
- Local whisper.cpp
- Custom OpenAI-compatible

The provider section should remain provider-neutral. Foil must not be presented
as Groq-only.

### Privacy And Reliability

Add a dedicated section or rail that calmly addresses trust and macOS workflow
reality.

Required points:

- API keys are stored in macOS Keychain.
- Transcription history stays on this Mac.
- Successful audio files are deleted after transcription.
- Failed audio may be retained locally only for retryable failures.
- Diagnostics are redacted and should not include API keys, transcript text,
  raw audio, or clipboard contents.
- macOS paste automation depends on Accessibility permission and target-app
  behavior.
- Foil provides History and clipboard fallback paths when a target app blocks
  paste automation.

This section should be visible and discoverable. Do not hide the paste caveat
or privacy posture behind tabs that a visitor might never open.

### Install

Keep Homebrew as the primary install path and manual DMG as the fallback.

Required behavior:

- Copy button still copies the Homebrew install command.
- Command remains readable on mobile.
- The manual DMG link points to GitHub Releases.
- The copy should state that Foil is beta software without sounding apologetic.

## Interaction Design

Keep the landing page static HTML/CSS with tiny vanilla JavaScript.

Required interactions:

- Existing install command copy button.
- Anchor navigation.

Allowed optional interaction:

- A small segmented feature switch if it improves scanning of the four feature
  groups without hiding essential content.

Do not introduce a new frontend framework for this pass.

## Visual Direction

Keep the existing Foil mark, teal and foil accent palette, real screenshots,
and 8px card/control radius.

Improve perceived quality through:

- Stronger typography hierarchy.
- More deliberate first-viewport composition.
- Denser proof strip.
- Better section pacing.
- Clearer separation between product proof, feature detail, provider choice,
  privacy/reliability, and install.
- Calm product-focused layout rather than decorative SaaS card clutter.

Avoid:

- Fake metrics.
- Unsupported claims.
- Generic dashboard mockups.
- Invented product screenshots.
- Hidden privacy or paste reliability caveats.
- A multi-page docs site.

## Accessibility And Responsive Requirements

- Navigation, buttons, copy controls, and any optional feature switch must be
  keyboard accessible.
- Hero, buttons, install command, and captions must not overflow on mobile.
- Screenshots should remain inspectable and not become tiny decorative images.
- Text should fit within buttons and cards without clipping.
- Motion should respect `prefers-reduced-motion`.
- Images must include useful alt text.

## Implementation Scope

Expected touched files:

- `site/index.html`
- `site/styles.css`

Potentially touched files only if the implementation needs them:

- `site/assets/screenshots/**` for newer verified screenshots.
- `README.md` only if public-facing site story changes create a mismatch with
  the README product preview.

Out of scope:

- App feature changes.
- New brand identity.
- New app icon.
- New framework or build step for the static site.
- Multi-page docs.
- Live release or GitHub Pages deployment verification unless the implementation
  is merged and published.

## Verification Plan

Use the website evidence guidance in `docs/acceptance-evidence.md`.

Before completion, try to disprove the strongest realistic failure modes:

1. The improved page hides or breaks important content on mobile.
   - Evidence: browser screenshot or inspection at a mobile viewport.
2. The page displays missing, stale, or unsupported media/claims.
   - Evidence: direct inspection of referenced image paths and visible copy.
3. The install command copy behavior regresses.
   - Evidence: browser interaction check or direct JavaScript inspection paired
     with a local browser smoke.
4. The page becomes less truthful about privacy, providers, or paste behavior.
   - Evidence: copy audit against README and `docs/acceptance-evidence.md`
     expectations.

For the final implementation handoff, include:

- Local preview URL or file path.
- Desktop and mobile browser evidence.
- `git diff --check`.
- Direct inspection of referenced paths/assets.
- A short evidence receipt using the repository's Claim / Strongest realistic
  failure mode / Evidence / Residual risk shape.
