# Usage Insights And Cleanup Groups Design

Date: 2026-07-05

## Status

Approved for spec writing on 2026-07-05.

## Objective

Add two major Foil features:

1. Usage Insights that help users understand their dictation usage and the apps
   where they use Foil most.
2. App-specific Cleanup Groups that replace the current universal cleanup
   toggle with user-managed groups, where each group owns its own cleanup
   behavior, provider, model, and prompt.

The design carries forward the useful Wispr Flow idea of showing usage across
apps, but keeps Foil's first pass focused on personal value stats instead of
coaching, streak pressure, voice profiles, or cleanup optimization advice.

## Product Decisions

Usage Insights v1 optimizes for personal value stats:

- Total words dictated.
- Estimated time saved.
- Dictation session count.
- Daily and weekly usage trends.
- Top apps by words and sessions.

Insights v1 should not include a cleanup usage summary, LLM-generated advice,
voice-profile interpretation, streak mechanics, or recommendations about where
cleanup should be enabled.

Cleanup customization should use named user-managed groups rather than hardcoded
app types or a global toggle plus overrides. Each app resolves to exactly one
group:

1. If the source app is assigned to a group, use that group.
2. If the source app is unassigned, use the default group.

This replaces the universal cleanup model. There should not be a separate
"cleanup on for all apps" toggle once groups are introduced. Today's universal
settings migrate into the default group, preserving behavior while removing
future logical contradictions.

## Existing Context

- `TranscriptProcessingMode` currently exposes `raw` and `cleanUp`.
- `AppState.transcriptProcessingMode` and cleanup provider/model fields define
  one global cleanup behavior today.
- `TranscriptionController.processTranscriptOrRaw` already runs cleanup after
  speech-to-text and falls back to raw text if cleanup fails.
- `TranscriptionHistory` already stores `sourceAppName` on records.
- `PasteTarget.captureCurrentTarget()` captures frontmost app name and process
  id, but does not currently store bundle identifier.
- The app shell currently has Workspace destinations for Home and History, and
  Preferences destinations including Cleanup.
- History storage can be disabled, so usage analytics must not depend on
  transcript text persistence.

## Usage Insights

Add a new app-shell Workspace destination named `Insights`.

Insights v1 should present:

- Summary counters for total words, sessions, and estimated time saved.
- A daily or weekly trend view derived from usage events.
- Top apps ranked by word count and session count.
- Empty states for new users and for users who disable usage analytics.

Time saved can use a simple deterministic estimate in v1. The exact constant
should be documented in UI copy or helper text, for example comparing dictated
word count against a conservative typing words-per-minute estimate. The estimate
must be presented as approximate.

Insights should not read transcript text. It should derive all values from a
separate usage event store.

## Usage Event Model

Introduce a non-content usage event model separate from `TranscriptionHistory`.
It should be stored even when transcript history storage is off, if the user
allows usage metrics.

Each usage event stores operational metadata only:

- Event id.
- Timestamp.
- Source app display name.
- Source app bundle identifier when available.
- Source app path when manually selected or otherwise known.
- Word count.
- Recording duration when available.
- Transcription duration when available.
- Cleanup duration when applicable.
- Cleanup group id and group name.
- Effective processing mode, raw or cleanup.
- Cleanup provider id and model metadata when cleanup is attempted.
- Outcome: success, transcription failure, cleanup fallback, or paste fallback
  if paste outcome is available at the time of recording.

Usage events must not store:

- Raw transcript text.
- Cleaned transcript text.
- Audio file paths.
- Prompt text.
- Vocabulary terms or corrections.
- API keys.
- Base URLs containing secrets.

Usage metrics should have independent storage controls. Turning off transcript
history should not imply turning off usage metrics; turning off usage metrics
should stop new event writes and give the user a clear way to delete retained
usage events.

## Cleanup Groups

Introduce `CleanupGroup`, a persisted user-managed preset:

- Stable id.
- Name.
- Sort order.
- Enabled state.
- App matchers.
- Processing mode: raw or cleanup.
- Cleanup provider id.
- Provider-specific model.
- Custom cleanup base URL when applicable.
- Custom prompt.
- Default-group marker.
- Created and updated timestamps.

App matching should prefer bundle identifier. Display name and selected app path
are fallbacks for apps without a reliable bundle id. A single app can belong to
only one group. If the user adds an app to a new group, Foil removes it from
the previous group.

Seed groups may include:

- `Agentic IDEs`
- `Terminal`
- `Messaging`
- `Email`
- `Default for unassigned apps`

Only the default group is required. Starter groups should not create confusing
assignments unless Foil can identify known apps confidently or the user adds
them.

Vocabulary and preferred terms remain global in v1. Per-group vocabulary is out
of scope because group-level provider, model, and prompt already add enough
configuration surface for the first pass.

## Cleanup Resolution

The transcription pipeline remains:

1. Capture the target app when recording starts, using bundle identifier when
   available.
2. Transcribe audio with the selected speech-to-text provider.
3. Resolve the captured app to a cleanup group.
4. If the resolved group uses raw mode, skip the cleanup provider request.
5. If the resolved group uses cleanup mode, send the raw transcript to that
   group's cleanup provider/model/prompt.
6. If cleanup succeeds, paste the cleaned transcript.
7. If cleanup fails, paste the raw transcript and mark cleanup fallback.
8. Record a non-content usage event.
9. Store transcript history only if history storage is enabled.

This means `effectiveTranscriptProcessingMode` becomes context-aware. The
global mode should be replaced by a resolver that accepts app context and
returns the resolved cleanup group plus effective cleanup configuration.

Cleanup failure remains non-blocking. A cleanup group with a missing API key,
invalid base URL, unavailable provider, or failed cleanup request must fall back
to raw transcript for that dictation.

## App Catalog And App Discovery

Add an app catalog that powers group membership editing. The Add App experience
uses a combined picker:

1. Suggested apps from Foil usage and app capture history.
2. Currently running apps from `NSWorkspace.shared.runningApplications`.
3. A manual `Choose from Applications...` fallback for installed apps that are
   not running and have not been seen by Foil.

Users should see app display names, and Foil should retain bundle identifiers
when available. If the user manually selects an app bundle, retain its path and
bundle identifier. If a manually selected app path later disappears, keep the
row but show the app as unavailable so the user can remove or replace it.

The picker should not require users to know bundle identifiers. Bundle ids are
technical metadata for reliable matching, not the main user-facing handle.

## UI

### Insights

Add `Insights` to the Workspace group in the app shell sidebar, likely after
Home and before History.

The page should include:

- A summary row for total words, sessions, and estimated time saved.
- A trend section for daily or weekly usage.
- A top-apps section showing app name, words, and sessions.
- Storage/privacy affordances that explain usage metrics are non-content
  metadata.

### Cleanup Settings

Replace the current universal cleanup settings pane with a group library and
detail layout:

- Left side: Cleanup Groups list.
- Detail pane: selected group editor.
- Group controls: create, rename, delete, reorder, and set default where
  applicable.
- App membership: list assigned apps, remove app, add app.
- Cleanup behavior: raw or cleanup.
- Cleanup provider/model/base URL/API key path when cleanup is selected.
- Prompt editor and reset prompt control when cleanup is selected.

The default group cannot be deleted. If a group is deleted, its apps become
unassigned and therefore use the default group.

The Home view can show the currently matched cleanup group near the recording
status or cleanup control. Detailed group editing belongs in Cleanup settings.
Any Home-level quick control must edit the resolved group or navigate to it; it
must not create a second global override.

## Migration

On first launch after the feature ships:

- Create `Default for unassigned apps`.
- If current `transcriptProcessingMode` is raw, set the default group to raw.
- If current `transcriptProcessingMode` is cleanup, set the default group to
  cleanup and copy current cleanup provider/model/base URL/custom prompt
  settings into the group.
- Preserve keychain storage behavior. Do not duplicate API keys into group
  records.
- Preserve global vocabulary and preferred terms.
- Optionally create starter groups without assigning apps unless known bundle
  ids are matched confidently.

After migration, the old global mode can remain as a compatibility read path
for older defaults, but the user-facing source of truth is cleanup groups.

## Privacy And Diagnostics

Diagnostics may log:

- Source app name and bundle id.
- Cleanup group id and name.
- Effective mode.
- Cleanup provider id and model.
- Durations.
- Input and output lengths.
- Fallback status and mapped error category.

Diagnostics must not log:

- Transcript text.
- Prompt text.
- Vocabulary content.
- API keys.
- Secret-bearing URLs.
- Audio paths from successful dictations.

Usage metrics should be described as local operational metadata unless a future
sync or cloud analytics feature is explicitly added.

## Error Handling

- Unassigned apps use the default group.
- Raw groups skip cleanup provider requests entirely.
- Cleanup groups with missing credentials, invalid provider configuration, or
  cleanup request failure paste the raw transcript and mark cleanup fallback.
- Duplicate app membership resolves by moving the app to the most recently
  edited group and removing it from other groups.
- Unavailable manually selected app paths remain visible and removable.
- Usage event writes should not block paste. If usage persistence fails, log a
  redacted diagnostic and continue the dictation flow.

## Testing And Evidence

Implementation should include focused tests for these claims:

- Usage metrics are stored when transcript history is off.
- Usage events contain word counts and app metadata but no transcript text.
- Raw cleanup groups skip cleanup provider requests.
- Cleanup groups use their own provider, model, and prompt.
- Unassigned apps resolve to the default group.
- An app can belong to only one group after add/move operations.
- Migration preserves current raw global behavior as a raw default group.
- Migration preserves current cleanup global behavior as a cleanup default
  group with the current provider/model/prompt.
- Cleanup failure in a group falls back to raw transcript.
- Diagnostics redact transcript text, prompts, vocabulary, API keys, and
  secret-bearing URLs.
- Insights derives totals and top apps from usage events, not transcript
  history records.
- The Add App picker combines seen apps, running apps, and manual app selection
  without requiring bundle id knowledge.

Acceptance evidence should follow `docs/acceptance-evidence.md`. The strongest
realistic failure modes are:

- The new group system accidentally still obeys an old global cleanup toggle,
  causing contradictory behavior.
- An agent/terminal group configured as raw still sends transcript text to a
  cleanup provider.
- Usage metrics store transcript content or stop working when transcript history
  is disabled.
- Migration changes existing users' cleanup behavior.

Required proof should include focused model/controller tests, request-count
tests around cleanup skipping, migration tests, diagnostics redaction tests, and
UI tests or direct screenshot inspection for Insights and Cleanup group editing.

## Out Of Scope For V1

- Cleanup optimization advice in Insights.
- Cleanup usage summaries in Insights.
- Voice profile generation.
- Streak mechanics.
- Per-group vocabulary.
- Team/shared groups.
- Cloud sync for usage events or cleanup groups.
- Automatic installed-app scanning beyond running apps, seen apps, and manual
  app selection.
- LLM-generated group suggestions.
