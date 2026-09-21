# Agent Vocabulary Intake Review

Date: 2026-09-21

## Decision

Build an agent-facing proposal path on top of Foil's existing local correction
engine. Do not add fuzzy matching, regex, project detection, or direct unattended
writes in the first version.

The current engine already handles the runtime correction problem. The missing
piece is a safe way for an agent to submit explicit spoken-form mappings such as:

```text
super base -> Supabase
superbase -> Supabase
super bass -> Supabase
```

Multiple explicit aliases provide predictable coverage without changing matching
semantics. Foil should show one review surface where the user can edit, preview,
scope, and apply the proposed mappings.

## What exists now

Foil 1.14.2 includes a deterministic local correction engine with:

- literal phrase rules and exact replacement text
- case-sensitive or ASCII case-insensitive matching
- Unicode word boundaries and NFC canonical equivalence
- global or Cleanup Group scope
- explicit enable and disable state
- protected backtick code, fenced code, and recognized web links
- stable overlap precedence and no recursive replacement
- a 1,000-enabled-rule and 64 KiB transcript envelope
- versioned atomic rule persistence with revision conflict detection
- preview through the production matcher
- recording-start snapshots so in-flight dictation keeps its captured rule revision
- original-text recovery and cleanup-failure fallback

The production contract currently passes all 150 development and held-out fixtures.
Recorded optimized warm p99 processing is 1.43 ms on Apple M2 and 5.23 ms on the
recorded Intel runner for 1,000 rules and 64 KiB input.

The Vocabulary UI remains the source of correction metadata. A Vocabulary pair can
be promoted into a linked local rule. This means an external tool must not edit the
local rule JSON directly: doing so would bypass Vocabulary metadata, UI management,
reconciliation, undo, and the app's compiled snapshot.

## Missing product surface

There is no supported external command or protocol through which Codex can:

1. discover valid Foil scopes;
2. submit one or more correction candidates;
3. preview conflicts and expected output;
4. hand the candidates to the user for review; or
5. receive a durable result indicating what the user applied.

This is a moderate integration task. It does not require changes to transcription,
matching, paste delivery, Cleanup providers, or project-context detection.

## Recommended first tranche

### User flow

1. A Foil Codex skill tells the agent when and how to propose vocabulary.
2. The agent submits a bounded JSON proposal containing explicit correction pairs,
   rationale, and a requested Foil scope.
3. Foil opens or surfaces a pending proposal sheet.
4. The sheet shows the source phrase, replacement, scope, conflicts, and a preview
   using the production engine.
5. The user edits or selects candidates and applies them.
6. Foil creates the Vocabulary pairs and linked local rules through one app-owned
   coordinator, then returns a receipt with applied, skipped, and rejected items.

An initial proposal can contain multiple spoken forms for one canonical term. Foil
may display them together, while storing them as the separate explicit rules the
current engine already supports.

### Minimal interface

Start with three operations:

- `scopes`: list enabled Cleanup Groups and the explicit global scope;
- `propose`: queue a bounded batch for review;
- `status`: return the disposition of a proposal.

Use a small packaged helper or plugin command that sends structured data to Foil.
The app owns all validation and persistence. A durable owner-only proposal inbox is
a suitable first transport because it works when Foil is closed: the helper writes
an atomic bounded proposal file, launches Foil, and Foil consumes it into the review
queue. Direct apply, broad rule listing, credentials, grants, MCP, and a long-lived
socket can wait until proposal behavior proves useful.

### Proposed request shape

```json
{
  "schema_version": 1,
  "request_id": "opaque-idempotency-key",
  "scope": { "kind": "cleanup_group", "id": "agents" },
  "corrections": [
    {
      "spoken_forms": ["super base", "superbase", "super bass"],
      "replacement": "Supabase",
      "note": "Project dependency"
    }
  ]
}
```

The request contains proposed rules only. It cannot read History, transcript text,
audio, provider credentials, or repository files through Foil.

## Why fuzzy matching should wait

The motivating examples are stable speech-recognition outputs and can be expressed
as explicit aliases. Fuzzy matching would introduce new behavior at every occurrence
of a near match. That raises ambiguity for short terms, ordinary words, code tokens,
and similar product names, and would require thresholds, tie-breaking, per-rule
controls, new performance bounds, and a new adversarial corpus.

Use explicit aliases first and collect concrete misses. Consider a matcher change
only when reviewed examples repeatedly require many unpredictable variants. The
first candidate should be a narrow, opt-in normalization such as whitespace or
punctuation tolerance for selected rules. General edit-distance matching should
remain a separate experiment with its own false-positive budget.

## Acceptance criteria

### Proposal contract

- Malformed, future-version, oversized, duplicate-ID, empty, overlong, ambiguous,
  and invalid-scope proposals are rejected without changing Vocabulary or rules.
- Replaying the same request ID produces the same disposition and no duplicates.
- A proposal accepted while Foil is closed appears after launch.
- More than one queued proposal cannot overwrite another.
- Proposal files and normal diagnostics contain no transcript, credential, or
  repository content supplied by Foil.

### Review and apply

- Review uses the production matcher for preview and reports exact conflicts before
  apply.
- The user can edit scope and aliases, omit individual candidates, or reject the
  batch.
- Applying `super base`, `superbase`, and `super bass` to `Supabase` creates three
  visible Vocabulary corrections and three linked rules with the chosen scope.
- Vocabulary metadata and local rules cannot diverge after a validation error,
  persistence failure, cancellation, relaunch, or concurrent UI edit.
- A stale proposal cannot overwrite a newer UI edit; it returns a conflict for
  review.
- The global local-corrections switch remains under user control. Applying a
  proposal does not silently enable it when it is off.

### End-to-end proof

- From a real Codex session, submit a proposal for `super base -> Supabase`, review
  and apply it in Foil, then dictate into Codex and read back `Supabase` from the
  destination.
- Reject a second proposal and prove it never affects dictation.
- Submit while Foil is closed, relaunch, apply, and verify the receipt and persisted
  UI state.
- Exercise duplicate submission, invalid scope, interrupted proposal write, failed
  Foil persistence, and concurrent UI editing.
- Re-run the existing 150-case engine gate and focused AppState, store, controller,
  History, and UI suites. The matcher output and performance budgets must remain
  unchanged.

## Later tranches

1. Add an explicit user grant for agents allowed to apply within selected scopes
   without reviewing every batch.
2. Add a thin MCP adapter only if it improves discovery over the Codex skill and
   packaged command.
3. Explore project-scoped packs after Foil can reliably identify the active project.
4. Evaluate narrow per-rule tolerance only from a reviewed corpus of real misses.

