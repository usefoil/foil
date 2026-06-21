# Live Audio Signifier Design

## Summary

Add a Whisperflow-inspired live audio signifier to Foil for macOS. The feature gives the user continuous visual confidence that Foil is present, that push-to-talk is active, and that the captured audio is moving through transcription and paste.

The approved product direction is:

- Keep the menu bar as the reliable always-available anchor.
- Add an always-visible floating capsule at bottom center.
- Show quiet idle dots while Foil is ready.
- Expand the capsule into live vertical bars while recording.
- Continue the capsule through the full session: processing, brief success/error, then return to idle.
- Treat the bars as approximate input-volume feedback, not a spectral analyzer or exact waveform.

## Reference Media

Reference movie and extracted frames are stored in [docs/mockups/live-audio-signifier](/Users/neonwatty/Desktop/foil/docs/mockups/live-audio-signifier):

- [wisprflow-visual-signifier.mov](/Users/neonwatty/Desktop/foil/docs/mockups/live-audio-signifier/wisprflow-visual-signifier.mov)
- [reference-idle.png](/Users/neonwatty/Desktop/foil/docs/mockups/live-audio-signifier/reference-idle.png)
- [reference-recording.png](/Users/neonwatty/Desktop/foil/docs/mockups/live-audio-signifier/reference-recording.png)
- [reference-processing.png](/Users/neonwatty/Desktop/foil/docs/mockups/live-audio-signifier/reference-processing.png)

## Goals

- Give immediate, low-attention feedback that the push-to-talk hotkey successfully opened the microphone.
- Make silence or microphone failure easier to notice while recording.
- Preserve Foil's current menu-bar workflow and existing detailed status HUD.
- Keep audio-level measurement lightweight enough to run from the existing recording tap without affecting captured audio quality or transcription behavior.
- Make the feature testable without live microphone hardware by isolating level sampling, smoothing, and presentation state.

## Non-Goals

- Do not build a spectrum analyzer, frequency visualization, or exact PCM waveform renderer.
- Do not change Foil's transcription provider behavior, paste routing, or captured audio format.
- Do not replace `FloatingStatusView`; it remains the detailed textual HUD for users who enable it.
- Do not add a new settings surface in the first implementation unless the implementation uncovers a strong accessibility or opt-out need. The initial behavior can be enabled by default because the user explicitly chose an always-visible capsule.

## Existing Context

Foil already has a good state foundation:

- [FoilApp.swift](/Users/neonwatty/Desktop/foil/Foil/FoilApp.swift) owns the `MenuBarExtra`, app delegate, recording controller, transcription controller, paste controller, and floating status panel.
- [AppState.swift](/Users/neonwatty/Desktop/foil/Foil/AppState.swift) owns high-level status (`idle`, `recording`, `transcribing`, `error`), timer state, transient success/error feedback, and menu bar presentation.
- [AudioRecorder.swift](/Users/neonwatty/Desktop/foil/Foil/AudioRecorder.swift) records through an `AVAudioEngine` input tap, converts buffers to Foil's target transcription format, and appends converted buffers for later encoding.
- [RecordingController.swift](/Users/neonwatty/Desktop/foil/Foil/RecordingController.swift) coordinates start, stop, cancel, and duration timing.
- [FloatingStatusView.swift](/Users/neonwatty/Desktop/foil/Foil/FloatingStatusView.swift) renders a detailed optional HUD at top right.

The new feature should use these boundaries rather than creating a parallel session state machine.

## UX States

### Idle

The capsule is visible at bottom center on the active screen's visible frame. It is small, black/material-backed, and contains subtle dot markers. It should not show text in the idle state.

The menu bar remains in its existing ready/setup/error form. The idle menu bar does not need a live waveform.

### Recording

When recording begins, the capsule expands from the idle dot pill into a wider rounded capsule with vertical white bars. The bars are driven by recent normalized input levels. The animation should communicate "the mic is live and receiving input" rather than exact signal detail.

The menu bar label also switches from the static waveform icon to a compact live-level indicator plus elapsed time. This keeps feedback available even if the capsule is covered, hidden by display arrangement, or visually missed.

### Processing

After the user releases push-to-talk, the capsule remains visible and changes to a processing state. It should stop showing input bars because the microphone is no longer open. Use a small spinner or pulsing dots inside the capsule to indicate transcription/cleanup/paste progress.

The menu bar keeps its current "Sending" / transcribing presentation unless the implementation naturally supports a compact spinner.

### Success

After successful paste or clipboard fallback, the capsule briefly shows a success state, then returns to idle. For direct paste success, use a short green check treatment. For clipboard fallback, use a warning/clipboard treatment consistent with existing menu-bar colors.

This should reuse the existing transient result timing where possible.

### Error And No Audio

For transcription errors, microphone start errors, and no-audio captures, the capsule briefly shows a warning state before returning to idle or remaining in warning if the app status remains error. Textual detail still belongs in the menu window or existing floating status HUD.

If no audio is captured, the capsule should make that visible enough to explain why nothing was pasted, but should not replace the existing `feedbackMessage` / `clipboardFeedback` details.

## Architecture

### Audio Level Sampling

Add lightweight level sampling to the recording path:

- Introduce an `AudioLevelSample` value type with at least `level: Double` and `capturedAt: Date`.
- Introduce an `AudioLevelObserving` callback or closure on `AudioRecording` so `AudioRecorder` can publish levels without exposing AVFoundation internals.
- Compute a normalized RMS level from the audio buffers already seen by the `AVAudioEngine` tap.
- Smooth the raw level with attack/decay behavior before publishing to UI state. A quick attack and slower decay should feel responsive while avoiding flicker.
- Throttle published updates to roughly 20-30 Hz. That is enough for fluid bars and avoids excessive main-actor churn.

The level computation should not mutate or replace the buffers used for transcription. It should be a read-only measurement from the same tap path.

### App State

Extend `AppState` with presentation-level audio state:

- `recordingAudioLevel: Double`
- `recordingAudioLevelHistory: [Double]`
- methods such as `recordAudioLevel(_:)` and `resetAudioLevels()`

Keep the data normalized in the range `0...1`. The view layer can map that range to bar heights.

`AppState.setStatus(.recording)` should reset stale levels. Returning to idle or entering transcribing should stop level updates and decay/collapse the visualization into the next state.

### Recording Wiring

`RecordingController` should configure the recorder's level callback when a recording starts and clear it when recording stops or cancels.

The controller is the best place to connect audio-level updates to `AppState` because it already owns the recording lifecycle and has an `AppState` reference. `AudioRecorder` should remain responsible only for capture and measurement.

### Capsule Panel

Add a dedicated bottom-center `NSPanel` managed by `AppDelegate`, similar in spirit to the existing floating status panel but separate in purpose:

- `LiveAudioSignifierPanel`: borderless nonactivating panel, clear background, floating level.
- `LiveAudioSignifierView`: SwiftUI view rendering the capsule states.
- The panel should be always visible while the app is running unless an implementation-time constraint requires a preference.
- Position at bottom center of the visible frame for the screen containing the mouse, matching the existing floating-status screen choice.
- Avoid stealing focus, keyboard events, or activation.

This panel is separate from `FloatingStatusView` because it is always-present and visual-only, while the current HUD is optional, textual, and top-right.

### Views

Create reusable visual components:

- `AudioLevelBarsView`: compact bars driven by a level history array.
- `LiveAudioSignifierView`: capsule shell and state switching.
- `MenuBarAudioLevelView`: tiny menu-bar rendering of the same level data.

The visual components should accept plain values rather than reaching into `AudioRecorder`. That keeps tests and previews simple.

### Lifecycle Mapping

`LiveAudioSignifierView` should derive presentation from `AppState.status` and existing transient fields:

- `idle`: idle dots.
- `recording`: live bars from `recordingAudioLevelHistory`.
- `transcribing`: processing dots/spinner.
- `idle` with `transientResult`: brief success/clipboard state.
- `error`: warning state.
- `idle` after `recordNoAudioCaptured()`: warning/no-audio state using existing feedback fields.

The implementation should avoid adding a new enum unless the derived mapping becomes hard to read. If a new presentation enum is useful, it should be pure and computed from `AppState`, not independently stored.

## Error Handling

- If the recorder cannot start, no level callback should remain installed and the capsule should show the same warning/error semantics as the rest of the app.
- If the input buffer has no channel data, level computation should publish no update rather than crash.
- If levels are silent, bars should shrink to a low baseline so the user can distinguish silence from a frozen UI.
- If the panel cannot position because no screen is available, skip repositioning and keep the app functional.
- If Accessibility or Microphone permissions are missing, the idle capsule remains present, while setup detail stays in the menu window.

## Testing

Unit tests should cover:

- RMS/normalization behavior for silence, quiet input, and loud input.
- Smoothing/decay behavior if implemented in a helper type.
- `AppState` level history reset and bounded history length.
- `RecordingController` clears or stops level updates on stop/cancel/failure.
- `LiveAudioSignifierView` presentation mapping for idle, recording, transcribing, success, clipboard fallback, no-audio, and error where practical.

Focused verification should include:

- `xcodebuild test` or the repo's focused test command for `FoilTests/AppStateTests`, `FoilTests/RecordingControllerTests`, and any new audio-level tests.
- A build or UI smoke check that proves the new `NSPanel` and menu bar label compile and render.
- For final acceptance evidence, the strongest realistic failure mode is that the visible bars animate but are not actually driven by microphone input. Rule that out by testing level computation directly with deterministic PCM buffers and by inspecting the recorder tap wiring from `AudioRecorder` through `RecordingController` into `AppState`.

## Open Implementation Decisions

- Exact idle capsule dimensions and animation durations should be tuned in implementation against screenshots.
- Decide whether the capsule should respect macOS Reduce Motion by disabling size interpolation or bar animation smoothing.
- Decide whether an opt-out preference is needed after the first implementation pass. The current design treats the always-visible capsule as the default product behavior.

## Acceptance Evidence Plan

Claim: Foil shows an always-visible bottom-center capsule and live recording bars driven by microphone level state.

Strongest realistic failure mode: The UI animates independently of real input levels, creating false confidence that the microphone is working.

Evidence: Deterministic audio-level unit tests, focused controller/state tests showing level propagation and reset behavior, and direct inspection of the `AudioRecorder` tap callback wiring.

Residual risk / follow-up: Hardware-specific microphone behavior can still differ by device. If implementation touches live capture behavior beyond read-only measurement, add `make test-microphone-live` or a manual live microphone smoke note.
