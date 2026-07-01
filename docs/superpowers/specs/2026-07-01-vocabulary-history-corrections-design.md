# Vocabulary History Corrections Design

Date: 2026-07-01

## Summary

Add Vocabulary as a cleanup-powered learning feature for recurring transcript
mistakes. Users teach Foil from real transcript history by selecting an
incorrect word or adjacent phrase, saving the correct version, and letting
future Cleanup requests use that correction as structured prompt context.

This is the next layer after transcript cleanup formatting. It should not
become a separate Wispr Flow-style Dictionary page in v1. History is the
creation surface. Cleanup settings are the management surface. Cleanup remains
the execution engine.

Reference mockup:

`docs/mockups/vocabulary-ux.html`

## Wispr Flow Notes

The local Wispr Flow research mapped a standalone Dictionary area with:

- personal and shared vocabulary scopes
- preferred words and visible add/edit/delete actions
- an implied correction mode for mapping a misheard phrase to a correct spelling
- dictionary behavior presented as something the product can learn
  automatically

Foil should borrow the product loop, not the full IA. The important lesson is
that vocabulary becomes useful when it is connected to real dictation mistakes.
Foil should avoid asking users to manage a blank glossary before they have a
concrete correction to save.

The "automatic" learning claim is only credible when the product observes a
correction signal. For Foil v1, the trustworthy signal is explicit user action
inside Foil History. Later, Foil can suggest corrections after a user edits a
history record, but it should not try to watch edits in third-party apps after
paste.

## Goals

- Let users correct recurring transcript mistakes from History with low
  friction.
- Store correction pairs such as `super base -> Supabase`.
- Keep preferred terms for cases where there is no known wrong phrase.
- Feed Vocabulary into the existing Cleanup request path as prompt context.
- Make the behavior private and explainable: Vocabulary applies during Cleanup
  and does not silently rewrite raw history.
- Add app-based History filters so users can find corrections by context, such
  as Messages, Linear, or Mail.

## Non-Goals

- Do not add a new top-level Dictionary/Vocabulary sidebar destination in v1.
- Do not perform blind find/replace before or after the LLM cleanup call.
- Do not mutate old raw transcripts when a correction is saved.
- Do not infer corrections by monitoring text changes in other apps after
  paste.
- Do not add team/shared vocabulary.
- Do not require live provider credentials for core test proof.

## Product Shape

Vocabulary has two entry types.

```text
Correction
- written as: super base
- correct version: Supabase

Preferred term
- term: Supabase
```

Corrections are stronger than preferred terms because they describe a concrete
mistake. Preferred terms remain useful for product names, acronyms, client
names, and technical strings that Cleanup should preserve or prefer.

When Cleanup runs, Foil assembles prompt context similar to:

```text
Vocabulary corrections:
- If the transcript says "super base", use "Supabase".

Preferred terms:
- Supabase
- Postgres
```

This context is advisory prompt input. It is not a deterministic replacement
engine.

If Cleanup is off, Vocabulary is saved but inactive. The UI must state this
clearly anywhere Vocabulary is edited.

## UX

### History

History should become the primary creation surface.

Add app-oriented filters above the transcript list:

```text
All apps | Messages | Linear | Mail | Failed
```

The app labels can start from whatever source-app metadata Foil currently has
or can reliably add. If source-app metadata is not available for old records,
show them under `Unknown` or only use app filters for records that have source
metadata.

Transcript rows should not use a vague `Open` action. Instead, the transcript
text itself is the correction surface:

```text
Can you update the docs for [super base +] auth before the release notes go out?
```

Clicking a word or phrase selects it as the "Foil wrote" value and shows a
small correction preview:

```text
Selected phrase: super base

Vocabulary will save a correction for super base from the selected Messages
transcript.

[Copy] [Paste Again] [Edit] [Continue to Vocabulary]
```

The exact selection mechanics can be conservative in v1:

- click a highlighted candidate phrase when Foil has one
- select text in the transcript and click `Continue to Vocabulary`
- or manually edit the "Foil wrote" field in the sheet

The product goal is that the user does not have to open a separate transcript
screen before teaching Foil.

### Correction Sheet

The sheet should be explicit and compact.

```text
Correct in Vocabulary

Teach Foil how this phrase should be written when Cleanup runs.

Foil wrote
[ super base ]

Use this instead
[ Supabase ]

Vocabulary applies during Cleanup. It does not change raw transcripts or
silently rewrite old history.

Optional note
[ product name, client name, acronym, or technical term ]

[Cancel] [Save] [Save and Re-clean]
```

`Save and Re-clean` immediately repairs the current transcript when Cleanup is
enabled and available. `Save` remains available for users who only want future
cleanup requests to learn from the correction.

### Cleanup Settings

Cleanup settings should manage Vocabulary.

```text
Vocabulary

Used as prompt context during Cleanup. Corrections are stronger than preferred
terms.

[Add Term] [Add Correction]

super base -> Supabase
Correction - created from History

open AI -> OpenAI
Correction - applies during Cleanup

Postgres
Preferred term
```

Settings is for review, edit, delete, and manual add. It should not be the only
way to create Vocabulary.

## Data Model

Add a persisted Vocabulary model separate from the raw custom cleanup prompt.

Minimum shape:

```swift
struct VocabularyCorrection: Codable, Identifiable, Equatable {
    var id: UUID
    var writtenAs: String
    var correctVersion: String
    var note: String?
    var sourceRecordID: UUID?
    var sourceAppName: String?
    var createdAt: Date
    var updatedAt: Date
}

struct VocabularyTerm: Codable, Identifiable, Equatable {
    var id: UUID
    var term: String
    var note: String?
    var createdAt: Date
    var updatedAt: Date
}
```

Normalization rules:

- trim leading/trailing whitespace
- reject empty `writtenAs`, `correctVersion`, or `term`
- dedupe corrections case-insensitively by `writtenAs` and `correctVersion`
- dedupe preferred terms case-insensitively by `term`
- preserve user-entered capitalization for display and prompt context

Existing `preferredTermsText` can be migrated or treated as the initial backing
store for preferred terms, but correction pairs need structured storage. Avoid
encoding correction pairs into the custom cleanup prompt.

## Architecture

Keep the cleanup pipeline from the transcript cleanup formatting design:

1. Speech-to-text returns a raw transcript.
2. `TranscriptionController` decides whether Cleanup runs.
3. `TranscriptionService` sends chat cleanup requests.
4. Cleanup failure falls back to raw text.
5. History stores only the final pasted text.

Add a small Vocabulary store/helper owned from `AppState` or a dedicated
observable model, then pass resolved Vocabulary context into
`TranscriptCleanupRequest`.

`TranscriptionController` should not assemble prompt strings directly. It should
resolve the cleanup request inputs and let a helper or `TranscriptionService`
construct the provider request body.

Diagnostics must not log:

- transcript text
- cleaned text
- custom prompt text
- vocabulary corrections
- preferred terms
- notes
- API keys or bearer tokens

Safe diagnostics can log counts:

- `vocabularyCorrectionCount`
- `vocabularyPreferredTermCount`
- cleanup provider/model
- cleanup applied/fallback status
- input/output lengths

## Implementation Slices

### PR 1: Vocabulary History UX

- Add structured Vocabulary storage and normalization.
- Add Cleanup settings management for corrections and preferred terms.
- Add History phrase-selection entry point and correction sheet.
- Feed corrections and terms into cleanup request prompt context.
- Prove diagnostics omit Vocabulary content.
- Add `Save and Re-clean` for a selected History record.
- Re-run Cleanup on the selected record using current settings and Vocabulary.
- Preserve the old record until the new result succeeds.
- Update the existing History item on successful re-clean.

## Testing And Evidence

The strongest realistic failure modes are:

- Vocabulary appears saved in UI but is not sent to Cleanup.
- Vocabulary secretly mutates raw history or performs blind replacement.
- Vocabulary leaks sensitive terms, correction pairs, or notes into diagnostics.
- History app filters mislead users because source-app metadata is missing or
  stale.
- Cleanup-off users think Vocabulary is active when it is not.

Required proof for PR 1:

- Focused `AppState` or Vocabulary store tests for persistence,
  normalization, dedupe, edit, and delete.
- Focused `TranscriptionService` tests proving cleanup request bodies include
  corrections and preferred terms as structured prompt context.
- Focused controller tests proving Cleanup off sends no Vocabulary context and
  Cleanup failure still falls back to raw text.
- Diagnostic redaction tests with sentinel correction/term/note strings.
- Focused `FoilUITests` coverage for:
  - app filters visible in History
  - phrase/correction entry point visible from a History record
  - correction sheet fields
  - Save and Re-clean updates the selected History record
  - Cleanup settings Vocabulary list and add/edit/delete controls
- Screenshot evidence for History phrase selection, correction sheet, and
  Cleanup settings Vocabulary.
- `git diff --check`.

If source-app metadata is not implemented in PR 1, the app filter UI must be
excluded or clearly marked unavailable. Do not show fake app filters against
records that cannot be filtered by app.

## Open Decisions

- Whether History phrase selection uses native text selection, explicit token
  chips, or both.
- Whether app filters are based on the active target app at paste time, the
  frontmost app at recording start, or another existing source-app signal.
