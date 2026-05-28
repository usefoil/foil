# T001 Scout Map - Queued Paste MVP

## Current Behavior Map

- `Foil/PasteQueue.swift` is an actor that serializes immediate paste jobs so concurrent transcription completions do not fight over focus. It drains automatically on enqueue and returns each `PasteDelivery` through a continuation. It is not a user-visible deferred queue.
- `Foil/PasteController.swift` owns current paste routing. `captureTarget()` only captures a `PasteTarget` when `appState.asyncPasteEnabled` is true. `paste(text:)` consumes `pendingTarget` and either enqueues into the immediate `PasteQueue` for original-target async paste or calls `TextInserter.insert` for current-app paste.
- `Foil/PasteTarget.swift` already captures the frontmost app PID, app name, optional AX window element, and optional SkyLight window ID. This is enough target metadata for PR 1.
- `Foil/FoilApp.swift` normal successful transcription flow adds history first, then delegates to `pasteController.paste(text:)`. Failure flow clears pending paste targets and preserves failed audio for retry except the no-API-key case.
- `Foil/AppState.swift` persists preferences in stored properties backed by `UserDefaults`. Existing async paste settings are `asyncPasteEnabled` and `experimentalSkyLightPasteEnabled`; both are reset and loaded through the existing defaults path.
- `Foil/SettingsView.swift` already has an Experimental tab with a `Paste Routing` section. This is the natural home for queued-paste enablement and mode controls.
- `Foil/MenuBarView.swift` has a compact control center with session strip, feedback panel, record controls, and last-result section. It already exposes callback hooks for paste/copy/retry style actions and accessibility IDs for UI testing.
- `Foil/TranscriptionHistory.swift` persists successful transcripts and failures separately. It is already the safety net and should remain independent of queue delivery success.
- `Foil/DiagnosticLog.swift` redacts sensitive text and records route/status details. New queue diagnostics should log IDs, counts, app names, statuses, bytes, and delivery routes, not full transcript text.
- `Foil/UITestingController.swift` has deterministic `--ui-testing` flows, seed arguments, a simulated transcription path, state snapshots, and command relays. It can be extended to seed or exercise queued paste without real microphone/API work.

## Recommended PR 1 Design Seam

Add a separate deferred queue/store instead of overloading `PasteQueue`.

Suggested model:

- `QueuedPasteMode`: `stepThrough` and `drain`, persisted in `AppState`.
- `QueuedPasteItem`: id, transcript text, recording start time, completion time, target metadata, status, failure reason, and optional last delivery.
- `DeferredPasteQueue` or `QueuedPasteStore`: `@MainActor @Observable` store with `items`, `pendingCount`, `enqueue`, `deliverNext`, `drain`, `markFailed`, `markPasted`, `copy`, `remove`, and retry-delivery operations.

Use `PasteQueue` only for actual delivery serialization when a queued item is delivered. This keeps the two meanings of queue clean:

- Existing `PasteQueue`: immediate low-level delivery serializer.
- New deferred queue/store: user-visible backlog of completed transcripts waiting for user-triggered paste.

## Flow Recommendation

1. At recording start, continue using existing target capture behavior when queued paste is enabled. A queued-paste target can reuse the same `PasteTarget.captureCurrentTarget()` pathway as async paste.
2. Store recording start time alongside the pending target. `AppState.recordingStartTime` is cleared when recording stops, so PR 1 likely needs a separate `pendingRecordingStartTime` or a small session context near `PasteController`/`AppDelegate`.
3. On successful normal transcription:
   - Always call `history.addSuccess(text:)` first, preserving the safety net.
   - If queued paste is enabled and a valid target exists, enqueue a deferred queue item and do not auto-paste.
   - If queued paste is disabled, preserve current paste behavior.
   - If queued paste is enabled but target capture failed, enqueue a `needsManualPaste` item or fall back by explicit product decision; do not silently discard.
4. Manual step-through delivery pastes exactly one pending item in start-time order.
5. Manual drain delivery attempts pending items in start-time order, retaining failed/needs-manual items.
6. Queue UI in `MenuBarView` should show count/status and item actions near the existing feedback/last-result surfaces.

## Likely Files Affected

Product:

- `Foil/AppState.swift` for queued-paste settings, mode persistence, status presentation, and maybe queue count summary.
- New `Foil/DeferredPasteQueue.swift` or equivalent for queue item state and delivery orchestration.
- `Foil/PasteController.swift` for delivery of queued items using existing target paste behavior and low-level `PasteQueue`.
- `Foil/FoilApp.swift` for wiring the deferred queue into the app delegate and normal transcription success path.
- `Foil/MenuBarView.swift` for queue count/status plus inspect/copy/remove/retry/step/drain controls.
- `Foil/SettingsView.swift` for Experimental setting and mode picker.
- `Foil/DiagnosticLog.swift` only if helper methods are desired; otherwise direct privacy-safe log messages are enough.
- `Foil/UITestingController.swift` for seed/simulated queue state and command hooks.
- `project.yml` and `Foil.xcodeproj/project.pbxproj` if adding a new Swift file requires project membership updates.

Tests:

- New `FoilTests/DeferredPasteQueueTests.swift` for ordering, step/drain, failed target retention, remove/copy/retry-like state transitions.
- `FoilTests/AppStateTests.swift` for settings persistence and default mode.
- `FoilTests/PasteControllerTests.swift` or new tests if delivery seams are added there.
- `FoilUITests/FoilUITests.swift` for settings visibility/persistence and queue count/status/actions in the control center.
- Existing `FoilTests/PasteQueueTests.swift` should remain focused on immediate delivery serialization.

## Risks And Questions

- Recording start time is currently UI/timer state, not durable session metadata. PR 1 needs a reliable source of start time that survives until transcription completion.
- `PasteTarget` contains `AXUIElement?`, so queued items may not be Codable. PR 1 does not need persistence across app relaunch unless desired; keep the active deferred queue in memory unless Judge decides otherwise.
- `retry` semantics for queued items should mean retry delivery, not retry transcription. Transcription retry already exists for failed history records.
- A queue item with no valid target should become `needsManualPaste` rather than falling back silently. Copy/manual paste must be available.
- In UI testing, current async paste route returns `.asyncQueued` and writes text to the pasteboard. That seam can keep tests deterministic for queued delivery.
- The MVP excludes global queued-paste hotkey and overlapping recording/transcription architecture.

## Suggested Worker Slice Candidates

1. One vertical Worker package:
   - Add queue settings and store.
   - Wire success path to enqueue instead of auto-paste when enabled.
   - Add menu controls and tests.
   - Best if Judge can set a broad allowed file list.
2. Two Worker packages:
   - Product behavior first: model/store, settings, app wiring, menu controls.
   - Test proof second: unit and UI tests for the oracle.
   - Matches existing board T003/T004 and keeps verification clearer.

Recommended: use two Worker packages but allow T003 to include minimal supporting tests if useful while implementing. T004 should close any remaining oracle coverage.
