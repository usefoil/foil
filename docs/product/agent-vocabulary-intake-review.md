# Agent Vocabulary Intake Review

Date: 2026-09-21

## Decision

Build an agent-facing proposal path on top of Foil's existing local correction
engine. Make a versioned local API owned by the Foil app the primary integration.
Run it only while Foil is open and the user-controlled **Agent Access** setting is
enabled. Do not require a plugin, skill, MCP registration, PATH modification,
helper installation, or separate download for the primary flow. Consider a bundled
CLI helper and STDIO MCP adapter later only if they materially improve discovery.
Do not add fuzzy matching, regex, project detection, or direct unattended writes in
the first version.

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

## Recommended architecture and staged delivery

The first product release consists of the user flow, Foil-owned local API, Agent
Access settings surface, instructions endpoint, vocabulary operations, proposal
review, and tests described below. The implementation plan divides that release
into Tranches 0–4. The CLI and MCP sections record possible later adapters; they are
not requirements for this release.

### User flow

1. The user opens Foil and enables **Agent Access**.
2. Foil starts its private local service and offers **Copy instructions for my
   agent**.
3. The agent calls Foil's stable local instructions endpoint.
4. The agent submits a bounded JSON proposal containing explicit correction pairs,
   rationale, and a requested Foil scope.
5. Foil opens or surfaces a pending proposal sheet.
6. The sheet shows the source phrase, replacement, scope, conflicts, and a preview
   using the production engine.
7. The user edits or selects candidates and applies them.
8. Foil creates the Vocabulary pairs and linked local rules through one app-owned
   coordinator, then returns a receipt with applied, skipped, and rejected items.

An initial proposal can contain multiple spoken forms for one canonical term. Foil
may display them together, while storing them as the separate explicit rules the
current engine already supports.

### Local API and process architecture

Foil owns a versioned HTTP-over-Unix-domain-socket API at a stable, documented path:

```text
~/Library/Application Support/Foil/agent-v1.sock
```

The socket directory and socket are owner-only. Foil accepts a deliberately small
HTTP subset with bounded headers and bodies, fixed content types, schema versions,
request IDs, and deadlines. The service is available only while Foil is running and
the user-controlled **Agent Access** setting is enabled. An agent cannot start Foil,
enable the service, or change that setting through the API.

The bootstrap endpoint is:

```sh
/usr/bin/curl --silent --show-error --retry 10 --retry-all-errors \
  --retry-delay 1 \
  --unix-socket "$HOME/Library/Application Support/Foil/agent-v1.sock" \
  http://foil/v1/instructions
```

It returns concise model-readable instructions, the API version, capability names,
privacy limits, example calls, and a link to the machine-readable schema. Foil also
exposes `GET /v1/openapi.json` over the same socket. This is the primary discovery
path and requires no agent-side installation or configuration.

This path is for agents running locally on the same Mac with shell access and
permission to reach the user's Foil Application Support directory. A remote or
web-only agent cannot reach a local Unix socket. A sandboxed local agent may require
the user's normal approval to run the bootstrap command, but it does not require an
integration package.

Avoid a TCP listener, background daemon, or reuse of the iPhone pairing bridge.
Unix socket permissions keep browsers and other user accounts outside the API. A
proposal remains inert until the user applies it in Foil.

No cross-agent standard makes arbitrary local app APIs appear automatically. Foil
must publish the stable bootstrap command in its UI and documentation. A **Copy
instructions for my agent** action can place a short prompt containing that command
on the clipboard. Once the agent runs it, the returned instructions and schema are
the complete discovery mechanism.

### Agent Access UX and lifecycle

Add an Agent Access section to Foil Settings:

```text
Agent Access                                      [ Off / On ]
Allow local agents on this Mac to inspect Vocabulary and submit changes for review.

Status: Off | Running | Error
[Copy instructions for my agent]
Pending proposals: 0
```

The setting defaults to off and persists the user's choice. When it is on, Foil
starts the service during normal app launch. The UI states that access exists only
while Foil is running and that agents can inspect Vocabulary but cannot read History,
audio, provider credentials, or project files.

Turning Agent Access off:

- stops accepting new connections;
- closes active connections;
- removes the socket;
- invalidates in-flight API requests;
- leaves applied Vocabulary and local rules unchanged; and
- retains already received proposals for review, with a separate action to discard
  them.

If service startup fails, the toggle returns to off, the socket is absent, and Foil
shows an actionable local error. It never falls back to TCP or a broader interface.

### Potential bundled CLI convenience after the first release

Add one native executable at a path such as:

```text
Foil.app/Contents/Helpers/foil-agent
```

Build, sign, notarize, update, and remove it with the Foil application. The existing
managed Whisper runtime provides a repository precedent for embedding and signing a
nested helper. The helper is a client of Foil's local API:

```text
foil-agent mcp
foil-agent instructions [topic]
foil-agent vocabulary scopes|list|preview|propose|status
```

The CLI commands are a quoting-safe convenience for agents and diagnostics. When
Foil is not running or Agent Access is off, the helper returns a clear unavailable
status; it cannot launch Foil or enable Agent Access. It does not need to be copied
out of the app or added to `PATH`; Foil can provide a **Copy agent command** action
containing its resolved absolute path.

`mcp` is an optional adapter that speaks MCP over standard input and output while
calling the same local API. Neither CLI nor MCP mode edits Vocabulary preferences or
the local-correction store directly.

Use peer-user validation, owner-only directory and socket permissions, bounded
request sizes, schema versions, request IDs, and deadlines. A proposal is inert
until the user applies it in Foil.

### Potential MCP registration after the first release

MCP is useful when a user wants Foil's tools to appear automatically in every Codex
task. It is not required for the local API or bundled CLI. Foil Settings may include
an optional **Expose Foil tools directly in Codex** action that registers the same
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

This is one-time configuration, not a second software installation. Codex requires
MCP configuration before it treats a server as an automatically available MCP tool.
The ChatGPT desktop app, Codex CLI, and IDE extension share MCP configuration on the
same Codex host. Users who only need occasional vocabulary work can skip this
entirely and give their agent the instructions command.

### Instructions and capability discovery

`GET /v1/instructions` returns versioned core guidance. Any later CLI or MCP adapter
must return the same guidance. It tells the agent:

- this server manages Foil vocabulary;
- read current state before proposing changes;
- use explicit spoken forms rather than fuzzy guesses;
- proposals require review in Foil; and
- Foil never exposes History, audio, credentials, or repository contents here.

The local API is self-describing without relying on an installed skill. A later CLI
equivalent could be `foil-agent instructions vocabulary --json`. In optional MCP
mode, Codex would read concise server-wide `instructions` during initialization and
could call a read-only `foil_get_instructions` tool for longer guidance by topic.

Potential MCP tools are:

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

Suggested routes:

```text
GET  /v1/instructions
GET  /v1/openapi.json
GET  /v1/vocabulary/scopes
GET  /v1/vocabulary
POST /v1/vocabulary/preview
POST /v1/vocabulary/proposals
GET  /v1/vocabulary/proposals/{id}
```

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

- With Foil running and Agent Access enabled, a fresh shell-capable agent can
  retrieve useful instructions with the documented `curl --unix-socket` bootstrap,
  without MCP, a skill, an `AGENTS.md` edit, a PATH change, or another installation.
- HTTP-over-Unix-domain-socket is the normative first-release interface. If a CLI or
  MCP adapter is added later, contract tests prove that it produces equivalent
  structured results for instructions, scopes, listing, preview, proposal, and
  status requests.
- The OpenAPI document matches every supported route, input, output, limit, and
  error exercised by contract tests.
- Malformed, future-version, oversized, duplicate-ID, empty, overlong, ambiguous,
  and invalid-scope proposals are rejected without changing Vocabulary or rules.
- Replaying the same request ID produces the same disposition and no duplicates.
- An attempted proposal while Agent Access is off fails to connect because no socket
  exists. It stores no proposal and does not launch Foil, enable access, or mutate
  files.
- More than one queued proposal cannot overwrite another.
- Proposal payloads and normal diagnostics contain no transcript, credential, or
  repository content supplied by Foil.

### Agent Access lifecycle

- Foil and FoilDev use isolated socket paths and stores; neither can read or mutate
  the other's state.
- The local API works immediately after installing and launching Foil, without any
  Codex or other agent configuration, once the user enables Agent Access.
- Agent Access defaults to off, persists the user's explicit choice, and starts only
  during Foil's normal app lifecycle.
- Enabling Agent Access creates an owner-only socket; disabling it closes existing
  connections and removes the socket.
- Service startup failure returns the setting to off, leaves no socket, and shows an
  actionable error without falling back to TCP.
- When Foil is closed or Agent Access is off, direct `curl` exits nonzero within a
  documented bound because no server is present. It never launches Foil, changes the
  setting, or writes app state directly as a fallback.
- Socket replacement, wrong owner, wrong peer user, protocol mismatch, oversized
  frames, schema version mismatch, and abrupt disconnect all fail without a
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
- Start Foil, enable Agent Access, and begin a fresh Codex task with no Foil MCP or
  skill installed. Give it only the documented Foil bootstrap command; verify that
  it reads the instructions, lists Vocabulary, previews a proposal, and submits it
  for review.
- Turn Agent Access off while a client is connected and prove the connection closes,
  new requests fail, the socket disappears, and no app data changes.
- Relaunch Foil with Agent Access on and off in separate runs and verify the service
  follows the persisted setting without an agent starting it.
- Reject a second proposal and prove it never affects dictation.
- Attempt submission while Foil is closed and prove it fails without mutation;
  relaunch Foil, submit after Agent Access starts, apply, and verify the receipt and
  persisted UI state.
- Exercise duplicate submission, invalid scope, interrupted proposal write, failed
  Foil persistence, and concurrent UI editing.
- Re-run the existing 150-case engine gate and focused AppState, store, controller,
  History, and UI suites. The matcher output and performance budgets must remain
  unchanged.

## Later tranches

1. Add a bundled, signed CLI helper only if shell quoting or socket diagnostics make
   direct `curl` too brittle in real use.
2. Add optional MCP registration only if automatic tool discovery is useful enough
   to justify configuration and stale-path repair.
3. Add an explicit user grant for agents allowed to apply within selected scopes
   without reviewing every batch.
4. Explore project-scoped packs after Foil can reliably identify the active project.
5. Evaluate narrow per-rule tolerance only from a reviewed corpus of real misses.

## Codex integration references

OpenAI's Codex MCP documentation states that Codex connects to configured servers,
supports STDIO MCP, consumes the initialization `instructions` field, shares MCP
configuration between the desktop app, CLI, and IDE extension, and supports
registration through `codex mcp add`. It does not document automatic discovery of
arbitrary local application servers. That is why MCP is optional here and Foil's
own instructions API is the zero-registration path. See:

- <https://developers.openai.com/codex/extend/mcp>
- <https://developers.openai.com/plugins/concepts/plugins>
