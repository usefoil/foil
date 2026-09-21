# Agent Vocabulary Intake Review

Date: 2026-09-21

## Decision

Build an agent-facing proposal path on top of Foil's existing local correction
engine. Ship the integration as a signed helper inside `Foil.app`, with STDIO MCP
and CLI modes in the same executable. Do not require a separately downloaded
plugin. Do not add fuzzy matching, regex, project detection, or direct unattended
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

1. Foil's MCP server instructions tell the agent when and how to propose vocabulary.
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

### Bundle and process architecture

Add one native executable at a path such as:

```text
Foil.app/Contents/Helpers/foil-agent
```

Build, sign, notarize, update, and remove it with the Foil application. The existing
managed Whisper runtime provides a repository precedent for embedding and signing a
nested helper. The helper has two front doors over one protocol client:

```text
foil-agent mcp
foil-agent instructions [topic]
foil-agent vocabulary scopes|list|preview|propose|status
```

`mcp` speaks MCP over standard input and output. The CLI commands expose the same
operations for agents without MCP support and for diagnostics. Neither mode edits
Vocabulary preferences or the local-correction store.

Foil owns a versioned local command service over a Unix-domain socket inside its
owner-only Application Support directory. The helper connects to that service. If
Foil is closed, the helper launches the installed app and retries for a short,
bounded interval. Avoid a persistent HTTP server, TCP listener, background daemon,
or reuse of the iPhone pairing bridge.

Use peer-user validation, owner-only directory and socket permissions, bounded
request sizes, schema versions, request IDs, and deadlines. A proposal is inert
until the user applies it in Foil.

### Codex setup without a separate plugin

Foil Settings should include an **Enable Codex integration** action. It locates the
installed `codex` command and uses Codex's supported MCP command to register the
bundled executable:

```text
codex mcp add foil -- /Applications/Foil.app/Contents/Helpers/foil-agent mcp
```

The displayed command must use Foil's actual resolved bundle path rather than
assuming `/Applications`. Foil verifies the resulting entry with `codex mcp get`
or `codex mcp list`. **Repair** replaces a stale path after the app moves, and
**Disable** uses `codex mcp remove foil`. If the Codex CLI cannot be found, show the
exact resolved command and a link to Codex's MCP settings instead of editing
`~/.codex/config.toml` directly.

This is one-time registration, not a second software installation. Codex requires
an MCP server to be configured before it will launch or trust a local executable.
The ChatGPT desktop app, Codex CLI, and IDE extension share MCP configuration on the
same Codex host.

### Agent discovery and instructions

The MCP initialization response includes concise server-wide `instructions`. Codex
reads that field alongside the server's tools, so the first 512 characters should
tell the agent:

- this server manages Foil vocabulary;
- read current state before proposing changes;
- use explicit spoken forms rather than fuzzy guesses;
- proposals require review in Foil; and
- Foil never exposes History, audio, credentials, or repository contents here.

Expose a read-only `foil_get_instructions` tool for longer, versioned guidance by
topic. It should return the supported workflow, examples, limits, and the current
API version. This makes the integration self-describing without relying on an
installed skill. The CLI equivalent is `foil-agent instructions vocabulary --json`.

The initial MCP tools are:

- `foil_get_instructions`
- `foil_list_vocabulary_scopes`
- `foil_list_vocabulary`
- `foil_preview_vocabulary_changes`
- `foil_propose_vocabulary_changes`
- `foil_get_proposal_status`

Tool names and descriptions should make the normal sequence apparent. Listing is
limited to Vocabulary terms, correction pairs, scopes, and rule state; it cannot
retrieve transcript History or other app data.

### Minimal application interface

Start with five operations:

- `scopes`: list enabled Cleanup Groups and the explicit global scope;
- `list`: return the Vocabulary entries the user has allowed the integration to
  inspect;
- `preview`: validate a candidate batch with the production matcher;
- `propose`: queue a bounded batch for review;
- `status`: return the disposition of a proposal.

The app owns all validation and persistence. Direct apply, credentials, autonomous
grants, repository inspection, and project detection can wait until proposal
behavior proves useful.

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

- MCP initialization returns valid, useful instructions and the six expected tools
  when launched directly from the signed app bundle.
- The CLI and MCP entry points produce equivalent structured results for the same
  instructions, scopes, listing, preview, proposal, and status requests.
- Malformed, future-version, oversized, duplicate-ID, empty, overlong, ambiguous,
  and invalid-scope proposals are rejected without changing Vocabulary or rules.
- Replaying the same request ID produces the same disposition and no duplicates.
- A proposal accepted while Foil is closed appears after launch.
- More than one queued proposal cannot overwrite another.
- Proposal payloads and normal diagnostics contain no transcript, credential, or
  repository content supplied by Foil.

### Packaging and lifecycle

- Foil and FoilDev contain separately identified, signed helpers and isolated local
  command endpoints; neither can read or mutate the other's store.
- Deep strict signature checks and notarization cover the nested helper in the DMG
  and installed application.
- Enabling the integration produces exactly one `foil` MCP entry pointing to the
  current signed helper. Repeated enable or repair operations create no duplicates.
- App upgrades preserve a working registration when the bundle path is unchanged.
  Moving the app produces a detected stale-path state with a working Repair action.
- Disabling removes only Foil's MCP entry and stops new helper access without
  changing existing Vocabulary or local rules.
- When Foil is closed, a tool call launches it and either completes through the
  private socket or returns a bounded actionable timeout; it never writes app state
  directly as a fallback.
- Socket replacement, wrong owner, wrong peer user, protocol mismatch, oversized
  frames, app/helper version mismatch, and abrupt disconnect all fail without a
  Vocabulary or rule mutation.

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
- Start a fresh Codex task after one-click registration and verify that Codex can
  discover the Foil instructions and tools without an installed Foil plugin or an
  `AGENTS.md` edit.
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
2. Add an optional skill only if richer workflow guidance materially improves on
   MCP server instructions and tool descriptions.
3. Explore project-scoped packs after Foil can reliably identify the active project.
4. Evaluate narrow per-rule tolerance only from a reviewed corpus of real misses.

## Codex integration references

OpenAI's Codex MCP documentation states that local Codex clients support STDIO MCP
servers, consume the initialization `instructions` field, share MCP configuration
between the desktop app, CLI, and IDE extension, and support registration through
`codex mcp add`. See:

- <https://developers.openai.com/codex/extend/mcp>
- <https://developers.openai.com/plugins/concepts/plugins>
