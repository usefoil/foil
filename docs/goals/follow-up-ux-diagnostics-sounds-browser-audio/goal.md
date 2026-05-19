# GroqTalk Follow-Up UX Goal Draft

## Objective

Implement three PR-sized GroqTalk follow-up improvements:

1. Privacy-preserving local diagnostics export for user-submitted bug reports.
2. User control over recording start and end sounds.
3. Off-by-default experimental browser media pause/mute while recording, starting with Chrome/Chromium feasibility.

Each batch should be completed, reviewed, PR'd, monitored to green CI, and merged before starting the next batch.

## Context

- GroqTalk is a macOS dictation app.
- Recent work added an audible app-owned recording-start cue and tests for delayed start cue scheduling.
- Users need local debugging evidence they can attach to GitHub issues.
- Diagnostics must be local only. No external telemetry, analytics, server upload, transcript upload, audio upload, or clipboard capture.
- Browser audio control is exploratory and must remain experimental/off by default.
- Local UI tests are disruptive on the user's machine and should not be run unless explicitly approved.

## Global Constraints

- Do not send logs, diagnostics, transcripts, audio, clipboard contents, API keys, or user content to external services.
- Do not include raw transcript text, raw audio, API keys, clipboard contents, or unredacted secrets in diagnostics exports.
- Preserve existing recording, transcription, paste, setup, and permission behavior unless a task explicitly changes it.
- Prefer small, testable units over app-delegate-only behavior.
- Keep experimental browser audio controls off by default.
- Pause and ask before using private macOS APIs, installing audio drivers, requiring a browser extension, or adding invasive permissions.
- Do not run local UI automation that takes over the user's screen unless explicitly approved.

## Batch 1: Local Diagnostics Export

### Task 1.1: Audit Existing Diagnostics

Acceptance criteria:

- Inventory current `DiagnosticLog` call sites.
- Identify missing lifecycle events for app launch, setup checks, permission state transitions, recording start/stop/cancel/failure, transcription start/success/failure, paste start/success/failure, keychain/API-key failures, and browser/media-control failures if relevant.
- Produce a short gap list in `docs/goals/follow-up-ux-diagnostics-sounds-browser-audio/notes/diagnostics-audit.md`.
- No product behavior changes are required for this task.

### Task 1.2: Add Structured Local Diagnostic Events

Acceptance criteria:

- Recording start, stop, cancel, and failure events are logged.
- Transcription start, success, and failure events are logged.
- Paste start, success, and failure events are logged.
- Setup check logs permission, microphone, and API-key state transitions.
- Logged transcription metadata includes provider/model IDs and timing, but not transcript text or audio content.
- Logged paste metadata includes delivery mode and timing, but not pasted text or clipboard contents.
- Logged errors use stable categories where practical.
- Unit tests or focused tests verify redaction for any new diagnostic formatting/redaction code.

### Task 1.3: Add Diagnostics Export UI/Flow

Acceptance criteria:

- User can export diagnostics from a discoverable local UI surface, such as `Help -> Export Diagnostics...` or a support area in Settings.
- Export writes a local file selected by the user.
- Export includes app version/build, macOS version, architecture, permission states, selected transcription provider/model names, setup status, and recent diagnostic log entries.
- Export excludes or redacts API keys, transcript text, raw audio, clipboard contents, and user content.
- Export is readable enough to attach directly to a GitHub issue.
- Export failure is surfaced to the user locally and logged without leaking sensitive content.

### Task 1.4: Batch 1 Verification

Acceptance criteria:

- `make build-warnings-as-errors` passes.
- `make test` passes.
- Focused diagnostics/redaction tests pass.
- Manual export creates a readable local diagnostics file with expected fields and no obvious secrets.
- Local disruptive UI automation is not run unless explicitly approved.

### Batch 1 PR Gate

Acceptance criteria:

- Run PR review toolkit / Superpowers extensively before creating the PR.
- Fix all actionable issues discovered.
- Create a PR with summary and verification evidence.
- Monitor CI until all required checks are green.
- Merge the PR before starting Batch 2.

## Batch 2: User-Controlled Start/End Sounds

### Task 2.1: Define Sound Cue Preferences

Acceptance criteria:

- Add a typed model for configurable recording sound cues.
- Supports at least `none`, the current start cue, the current stop cue, and one alternate cue.
- Start and end cue preferences are stored independently.
- Defaults preserve current behavior.
- Global sound effects toggle still disables both cues.

### Task 2.2: Add Settings UI for Sound Controls

Acceptance criteria:

- User can independently configure recording start and recording end sounds.
- User can disable either cue without disabling all app sounds.
- User can preview each cue.
- UI fits the current Settings organization and does not crowd the existing pane.
- Labels are succinct and understandable without explanatory wall text.

### Task 2.3: Wire SoundPlayer to Preferences

Acceptance criteria:

- `SoundPlayer` plays the selected start cue.
- `SoundPlayer` plays the selected end cue.
- `none` suppresses only the selected cue.
- The global sound-effects setting suppresses both cues.
- The current audible start cue remains audible in normal use.
- The current stop cue behavior remains available.

### Task 2.4: Batch 2 Tests and Verification

Acceptance criteria:

- Unit tests cover default start/end cue behavior.
- Unit tests cover `none` for start and end independently.
- Unit tests cover separate start/end choices.
- Unit tests cover the global sound-effects toggle overriding both cues.
- `make build-warnings-as-errors` passes.
- `make test` passes.
- Manual preview verifies each selectable cue plays or suppresses as expected.

### Batch 2 PR Gate

Acceptance criteria:

- Run PR review toolkit / Superpowers extensively before creating the PR.
- Fix all actionable issues discovered.
- Create a PR with summary and verification evidence.
- Monitor CI until all required checks are green.
- Merge the PR before starting Batch 3.

## Batch 3: Experimental Browser Media Pause/Mute While Recording

### Task 3.1: Browser Audio Control Discovery Spike

Acceptance criteria:

- Determine feasible Chrome/Chromium control options using supported macOS mechanisms, AppleScript, accessibility, or browser scripting.
- Compare `pause media` vs `mute browser/tab` for reversibility and user surprise.
- Document findings and recommendation in `docs/goals/follow-up-ux-diagnostics-sounds-browser-audio/notes/browser-audio-discovery.md`.
- Document required permissions and failure modes.
- Do not ship enabled product behavior in this task unless needed behind an explicit experimental flag.

### Task 3.2: Add Experimental Setting

Acceptance criteria:

- Add an off-by-default Experimental setting for browser media control while recording.
- Setting name is explicit, such as `Pause browser media while recording`.
- UI states supported browser scope clearly and succinctly.
- Setting persists across app launches.
- No behavior changes occur when the setting is off.

### Task 3.3: Implement Browser Media Controller

Acceptance criteria:

- On recording start, if enabled, attempts to pause or mute supported browser media according to the discovery recommendation.
- On recording stop, cancel, or error, avoids unexpectedly starting media that was already paused before GroqTalk acted.
- Handles browser not running.
- Handles unsupported browser or script/accessibility failure without blocking recording.
- Logs local diagnostic success/failure categories without capturing URL, page title, transcript text, or browser content.
- Browser media behavior remains isolated from transcription and paste flows.

### Task 3.4: Batch 3 Tests and Verification

Acceptance criteria:

- Unit tests cover controller state transitions.
- Unit tests cover browser-not-running and command-failure paths.
- Unit tests cover that recording proceeds when browser control fails.
- Manual test with Chrome/Chromium playing media confirms enabled behavior pauses/mutes media on recording start.
- Manual test confirms already-paused media is not resumed unexpectedly.
- `make build-warnings-as-errors` passes.
- `make test` passes.

### Batch 3 PR Gate

Acceptance criteria:

- Run PR review toolkit / Superpowers extensively before creating the PR.
- Fix all actionable issues discovered.
- Create a PR with summary and verification evidence.
- Monitor CI until all required checks are green.
- Merge the PR.

## Overall Stop Rules

- Stop after each PR is merged and confirm before starting the next batch if scope has changed.
- Pause if a task requires private APIs, browser extensions, audio drivers, new external services, or sensitive data capture.
- Pause if CI cannot be made green without changing unrelated behavior.
- Pause if local manual verification requires disruptive UI automation on the user's active machine.

## Suggested Initial GoalBuddy Prep Input

Use this file as source material and create a GoalBuddy board with three milestones:

1. Local Diagnostics Export
2. User-Controlled Start/End Sounds
3. Experimental Browser Media Pause/Mute

Each milestone should include implementation tasks, test tasks, and a PR gate task with the acceptance criteria listed above.

## Canonical Board

Machine truth lives at:

`docs/goals/follow-up-ux-diagnostics-sounds-browser-audio/state.yaml`

If this charter and `state.yaml` disagree, `state.yaml` wins for task status, active task, receipts, verification freshness, and completion truth.

## Run Command

```text
/goal Follow docs/goals/follow-up-ux-diagnostics-sounds-browser-audio/goal.md.
```

## PM Loop

On every `/goal` continuation:

1. Read this charter.
2. Read `state.yaml`.
3. Run the bundled GoalBuddy update checker when available and mention a newer version without blocking.
4. Work only on the active board task.
5. Do not run disruptive local UI automation unless explicitly authorized.
6. Write a compact receipt and update the board.
7. Continue to the next largest safe local work package unless blocked by a stop rule.
8. Finish only with a Judge or PM audit receipt that maps verification back to the original outcome and records `full_outcome_complete: true`.
