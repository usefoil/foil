# E2E Transcription Testing — Design Spec

**Date:** 2026-05-14
**Goal:** Automated end-to-end testing of the full transcription pipeline using pre-recorded audio, without requiring a microphone.

## Problem

The app's transcription pipeline (record → encode → send to Groq API → receive text → paste) cannot be tested end-to-end in CI or automated local runs because it requires live microphone input. Existing integration tests verify the API accepts audio formats but use sine waves, which produce no meaningful transcription. There is no way to verify that real speech → real text works without a human.

## Approach

Inject a pre-recorded speech audio file at the `RecordingController` level using a stub `AudioRecording` conformer, then let the rest of the pipeline run unmodified — real `TranscriptionController`, real Groq API, real history logging, real paste delivery. Verify the result through the UI via XCUITest.

## Architecture

### Audio Generation

Use macOS `say` to synthesize a known phrase into a WAV file at test time:

```bash
say "the quick brown fox jumps over the lazy dog" \
    -o /tmp/groqtalk-e2e.wav \
    --file-format=WAVE --data-format=LEI16@16000
```

- Deterministic: same text → same audio on a given macOS version
- No bundled assets: generated fresh each run
- CI-compatible: `say` is available on all macOS runners
- Format: 16-bit PCM, 16kHz mono (matches the app's internal format)

### E2EAudioStub

A new `AudioRecording` conformer gated behind `#if DEBUG`:

```swift
#if DEBUG
final class E2EAudioStub: AudioRecording {
    private let fileURL: URL
    
    init(fileURL: URL) { self.fileURL = fileURL }
    
    func startRecording() throws { /* no-op */ }
    func stopRecordingAsync(format: AudioFormat) async throws -> URL { fileURL }
    func cancelRecording() { /* no-op */ }
    var isRecording: Bool { false }
}
#endif
```

**File:** `GroqTalk/E2EAudioStub.swift` (new)

The stub does nothing on start/cancel and returns the pre-generated WAV file URL on stop. This exercises the real `RecordingController` delegate callbacks (`didStopWithURL`, format handling) without touching the microphone.

### RecordingController Changes

`RecordingController` already takes an `AudioRecording` via init. The only change needed is exposing a way for `UITestingController` to create a `RecordingController` with the stub and swap it into the `AppDelegate`. This requires either:

- Making `AppDelegate.recordingController` settable from `UITestingController`, or
- Passing the audio recorder choice through the existing `UITestingController` callbacks

The simpler path: add a callback to `UITestingController` (like the existing `onStartRecording`, `onStopRecording` etc.) that replaces the recording controller. Specifically, add an `onReplaceRecordingController: (RecordingController) -> Void` callback that `AppDelegate` implements by swapping its `recordingController` property and wiring the delegate.

### UITestingController E2E Method

Add `configureE2ETranscribeIfNeeded()` called during `applicationDidFinishLaunching`:

```
detect --e2e-transcribe in launch arguments
  → generate WAV via say command
  → create E2EAudioStub with the WAV URL
  → create new RecordingController with stub
  → wire delegate to AppDelegate (same as normal)
  → replace appDelegate.recordingController
  → trigger startRecording() then stopRecording()
  → real pipeline takes over from didStopWithURL
```

The method is called alongside existing `configureUITestingIfNeeded()` and `configureAutomationSmokeIfNeeded()`.

### Data Flow

```
XCUITest launches app with --e2e-transcribe
  └─ UITestingController.configureE2ETranscribeIfNeeded()
      ├─ say "the quick brown fox..." → /tmp/groqtalk-e2e.wav
      ├─ E2EAudioStub(fileURL: .wav)
      ├─ RecordingController(audioRecorder: stub, appState:)
      ├─ recordingController.delegate = appDelegate
      ├─ recordingController.startRecording()  → stub no-ops
      └─ recordingController.stopRecording()   → stub returns wav URL
          └─ AppDelegate.recordingController(didStopWithURL:format:)
              └─ TranscriptionController.transcribe(audioURL:, format: .wav)
                  └─ TranscriptionService → real Groq API
                      └─ AppDelegate.transcriptionController(didTranscribe:)
                          ├─ history.addSuccess(text:)
                          └─ pasteController.paste(text:)
```

## Verification

### Normalization

Both expected and actual strings are normalized before comparison:

- Lowercase
- Strip punctuation (keep only alphanumeric and spaces)
- Collapse whitespace to single spaces
- Trim

Example: `"The Quick Brown Fox!"` → `"the quick brown fox"`

### Assertion

Split the expected phrase into words. Assert each word appears in the normalized transcription. Fail with a message showing which words were missing.

This tolerates Whisper adding/changing punctuation, capitalization, or minor filler words, while catching real transcription failures (wrong language, empty result, garbled text).

### Error Detection

If the Groq API call fails, the app state goes to `.error(...)` and the menu bar icon changes. The UI test detects this and fails with the error message from the UI, distinguishing API failures from assertion failures.

### Timeout

30 seconds total. `say` generation takes ~1s, Groq API typically responds in 2-5s. The remaining margin handles CI variability.

## UI Test

**File:** `GroqTalkUITests/GroqTalkUITests.swift` (add test)

```
func testE2ETranscription():
    set GROQ_API_KEY env var (from launchctl or test config)
    launch app with --e2e-transcribe --ui-testing
    wait for menu bar icon to settle (not .transcribing)
    click menu bar icon to open popover
    find last history entry text
    normalize and assert word-by-word match
    if error state detected → fail with error message
```

The test is gated behind `GROQ_API_KEY` being set — skipped otherwise. The API key reaches the app via the macOS keychain (already populated by `security add-generic-password` or `launchctl setenv` in CI). The UI test does not need to pass the key as a launch argument.

## CI Workflow

**File:** `.github/workflows/e2e.yml` (extend)

Add a step after the existing integration tests that runs the E2E UI test:

```yaml
- name: Run E2E transcription UI test
  env:
    RUN_LIVE_GROQ_TESTS: "1"
    GROQ_API_KEY: ${{ secrets.GROQ_API_KEY }}
  run: |
    launchctl setenv GROQ_API_KEY "$GROQ_API_KEY"
    xcodebuild test \
      -scheme GroqTalk \
      -destination 'platform=macOS' \
      -only-testing:GroqTalkUITests/GroqTalkUITests/testE2ETranscription \
      | xcpretty --color && exit ${PIPESTATUS[0]}
```

## Files Changed

| File | Change | Lines |
|------|--------|-------|
| `GroqTalk/E2EAudioStub.swift` | New — `AudioRecording` stub, `#if DEBUG` | ~20 |
| `GroqTalk/UITestingController.swift` | Add `configureE2ETranscribeIfNeeded()` | ~40 |
| `GroqTalk/GroqTalkApp.swift` | Call new E2E method in `applicationDidFinishLaunching`, expose `recordingController` for replacement | ~10 |
| `GroqTalkUITests/GroqTalkUITests.swift` | Add `testE2ETranscription()` | ~40 |
| `.github/workflows/e2e.yml` | Add E2E UI test step | ~15 |
| `GroqTalk.xcodeproj/project.pbxproj` | Register `E2EAudioStub.swift` | ~10 |

**Not touched:** `TranscriptionController`, `TranscriptionService`, `RecordingController` (protocol already supports injection), `PasteController`, `AppState` — all exercised as-is.

## Out of Scope

- Testing the actual microphone capture (requires hardware)
- Testing paste delivery to a specific target app (requires accessibility + target app)
- Multiple language testing (could be added later with different `say -v` voices)
- Performance benchmarking of transcription latency
