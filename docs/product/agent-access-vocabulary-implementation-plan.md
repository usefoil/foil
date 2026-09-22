# Agent Access Vocabulary Implementation Plan

Date: 2026-09-21
Status: Proposed
Design basis: `docs/product/agent-vocabulary-intake-review.md`

## Outcome

Ship a user-controlled **Agent Access** service inside Foil. While Foil is open and
Agent Access is enabled, a local shell-capable agent can retrieve instructions,
inspect allowed Vocabulary state, validate correction candidates, and submit a
proposal. The user reviews and applies the proposal in Foil. No plugin, skill, MCP
registration, helper installation, PATH change, TCP listener, background daemon, or
unattended write is required.

The first release is complete only when a fresh Codex task can use the copied
bootstrap command to propose `super base -> Supabase`, the user can review and apply
it, and dictation uses the resulting local correction.

## Product boundaries

### Included

- An Agent Access setting that defaults to off and persists the user's choice.
- A Foil-owned HTTP service over an owner-only Unix domain socket.
- A self-describing instructions endpoint and checked contract document.
- Read-only scope, vocabulary, and preview operations.
- A durable, idempotent proposal queue.
- A Foil review surface with edit, omit, reject, and apply actions.
- One app-owned commit path for Vocabulary metadata and linked local rules.
- Foil/FoilDev/test isolation, privacy-safe diagnostics, and installed-app proof.

### Deferred

- MCP registration, a bundled CLI helper, skills, or plugins.
- Direct agent apply or scope-level unattended grants.
- Agent access to History, audio, credentials, provider configuration, project
  files, clipboard contents, or the active application.
- Project detection, fuzzy matching, regex rules, or matcher changes.
- Remote or web-only agent access.

## Architecture decisions

### Process and lifecycle

- The service runs in the Foil process. `AppDelegate` owns an
  `AgentAccessController`, starts it only after the single-instance launch gate has
  succeeded, and stops it from `applicationWillTerminate`. Service startup never
  occurs from `AppState.init`.
- `AppState` exposes observable intent and presentation state: enabled preference,
  `off | starting | running | error`, an actionable error, and pending count.
- Only the user can enable Agent Access. Foil may turn the persisted preference off
  after a startup or ownership failure. API calls cannot launch Foil, enable Agent
  Access, or change the preference.
- On launch, `AppDelegate` starts the controller only when the persisted preference
  is enabled. Turning the setting off closes listeners and active connections,
  removes the socket, and invalidates in-flight requests.
- Startup is fail-closed. A bind, ownership, or path failure returns the setting to
  off and leaves no socket. There is no TCP fallback.

### Paths and isolation

Derive paths from `AppBrand.applicationSupportDirectoryName` so production and
development builds cannot collide:

```text
~/Library/Application Support/Foil/agent-v1.sock
~/Library/Application Support/Foil/agent-vocabulary-proposals-v1.json

~/Library/Application Support/Foil Dev/agent-v1.sock
~/Library/Application Support/Foil Dev/agent-vocabulary-proposals-v1.json
```

Unit and UI tests receive explicit temporary paths. No test uses the production
Application Support directory.

### Transport and protocol

- Use a small transport abstraction so parsing and routing tests do not require a
  live socket.
- Use a focused Darwin `AF_UNIX` implementation with
  `socket`/`bind`/`listen`/`accept` and verify accepted peers with `getpeereid`.
  POSIX transport makes peer identity, filesystem permissions, and teardown
  testable without a TCP or launchd listener.
- Create the containing directory owner-only and make the socket owner-only. Refuse
  a pre-existing non-socket, symlink, wrong-owner socket, or path outside the
  expected support directory.
- Reject a socket path that cannot fit in `sockaddr_un.sun_path` with an actionable
  startup error; never truncate it.
- Accept one bounded HTTP/1.1 request per connection. Support only the documented
  methods, exact paths, `application/json`, and a fixed maximum body. Reject chunked
  bodies, conflicting content lengths, path traversal, duplicate security-sensitive
  headers, invalid UTF-8, and unsupported versions.
- Suggested first-release limits: 16 KiB headers, 64 KiB body, 50 correction pairs,
  10 spoken forms per pair, 256 Unicode scalars per phrase, and a five-second
  request deadline. Put every limit in the instructions and OpenAPI contract.
- Route all state access to `@MainActor`; keep socket I/O and parsing off the main
  thread. Cancellation must prevent a late main-actor mutation.

### API

```text
GET  /v1/instructions
GET  /v1/openapi.json
GET  /v1/vocabulary/scopes
GET  /v1/vocabulary
POST /v1/vocabulary/preview
POST /v1/vocabulary/proposals
GET  /v1/vocabulary/proposals/{id}
```

All JSON responses include `schema_version` and `request_id`. Errors use one stable
shape with a machine-readable code and safe user-facing message. The server never
returns History, transcript content, audio paths, credentials, repository content,
or provider configuration.

`preview` validates the proposed mappings with the production local correction
compiler and returns conflicts, duplicates, normalized values, scope validity, and
synthetic examples. It compiles the hypothetical candidate set independently of the
global local-corrections switch, so a disabled switch does not produce a misleading
no-op preview. It does not persist the request. If caller-supplied sample text is
later accepted, cap it separately, process it only in memory, and prove it never
enters proposals or diagnostics.

### Persistence and apply integrity

Today Vocabulary correction metadata is stored in `UserDefaults`, while linked
local rules are stored in `local-corrections-v1.json`. Agent batch apply must not
write those two sources independently.

Before enabling proposal apply, introduce one atomic catalog commit path in a new
`vocabulary-catalog-v2.json` file. It stores:

- Vocabulary correction metadata;
- linked executable rules and the global enabled flag; and
- a bounded applied-proposal receipt ledger used for idempotent recovery.

Migrate existing UserDefaults corrections and the schema-v1
`local-corrections-v1.json` snapshot without changing IDs, timestamps, order,
enabled state, case sensitivity, or scope. Current Foil uses the v2 catalog after a
successful atomic write and leaves both legacy sources untouched. The catalog
records a fingerprint of those sources at migration. A previous Foil release
therefore sees its consistent pre-upgrade state. If that release changes legacy
state during a downgrade, current Foil detects the fingerprint mismatch on the next
upgrade and fails closed into an explicit reconciliation path rather than silently
discarding either side. A failed or interrupted migration leaves no active v2
catalog and the prior release's state remains readable.

All existing UI mutation methods and agent proposal apply call a new
`VocabularyCorrectionCoordinator`. It validates and compiles the complete target
snapshot before one atomic save, then publishes the in-memory state. A revision
captured when the proposal was received prevents a stale proposal from overwriting
newer UI edits. The applied-proposal ledger makes a replay return the original
receipt without creating duplicates, including after a crash between catalog and
proposal-queue updates.

Pending proposals are inert and live in their own versioned atomic store. They may
survive Agent Access being disabled or Foil quitting so the user can still review or
discard work already received. The API cannot read them while access is off because
the server is absent.

### Diagnostics

Log lifecycle, route, result code, byte counts, duration, proposal ID, and request-ID
digest. Never log request bodies, correction strings, vocabulary values, sample
text, transcript content, socket payloads, or full request IDs. Contract tests scan
captured diagnostics for seeded secrets and phrases.

## Delivery tranches

Each tranche should be a reviewable PR. Do not begin a later tranche until the prior
acceptance gate is green and its strongest failure mode has recorded evidence.

### Tranche 0 — Contract and Unix-socket proof

**Status:** implemented and acceptance-gated on 2026-09-21. See the
[Tranche 0 evidence receipt](../evidence/agent-access-vocabulary/tranche-0/receipt.md).

**Purpose:** retire the risky transport and protocol assumptions without adding a
user-visible setting or allowing mutation.

Implementation:

- Define versioned request/response DTOs, limits, stable errors, proposal states,
  instructions content, and an OpenAPI fixture.
- Add a brand-aware `AgentAccessPaths` resolver with explicit temporary-path
  overrides for tests.
- Add an injectable POSIX Unix-socket transport and bounded HTTP/1.1 parser/router.
- Expose instructions and OpenAPI from a test host only; do not wire service startup
  into Foil yet.
- Add a real `/usr/bin/curl --unix-socket` integration test.

Primary files:

- new `Foil/AgentAccessModels.swift`
- new `Foil/AgentAccessPaths.swift`
- new `Foil/AgentAccessHTTP.swift`
- new `Foil/AgentAccessServer.swift`
- new `Foil/Resources/AgentAccessOpenAPI.json`
- `Foil.xcodeproj/project.pbxproj`
- new `FoilTests/AgentAccessHTTPTests.swift`
- new `FoilTests/AgentAccessServerTests.swift`

Acceptance:

- The support directory and socket are owner-only, and accepted clients must pass
  same-user `getpeereid` verification.
- Stale sockets are removed only after type, owner, path, and symlink checks. Regular
  files, foreign sockets, and attacker-controlled links remain untouched.
- Overlong Unix paths fail visibly and are never truncated.
- Split reads, slow headers, partial bodies, oversized headers/bodies, duplicate or
  conflicting content lengths, chunked bodies, invalid UTF-8, traversal, unsupported
  methods/content types, deadlines, and disconnects all terminate safely.
- Stop closes accepted connections and removes only the socket created by that server
  instance.
- Foil, Foil Dev, and tests resolve distinct paths.
- OpenAPI and instructions enumerate exactly the implemented routes, limits, privacy
  exclusions, and fixed bootstrap command.

### Tranche 1 — Read-only Agent Access vertical slice

**Purpose:** deliver the safe, zero-registration discovery path before accepting
proposals or changing Vocabulary.

Implementation:

- Add `AgentAccessController`, owned by `AppDelegate` after the single-instance gate.
- Add the persisted, default-off setting and observable
  `off | starting | running | error` presentation state.
- Add Agent Access controls to General settings: toggle, status, Copy instructions,
  and a clear disclosure that local processes running as the same macOS user can
  read the allowed Vocabulary fields while access is enabled.
- Implement instructions, OpenAPI, scopes, vocabulary list, and hypothetical preview.
- Return purpose-built API DTOs; do not serialize `VocabularyCorrection` directly or
  expose `sourceRecordID`, source app, timestamps not needed by the contract,
  transcript linkage, provider data, or repository information.
- Do not write a discovery manifest in the first release. The fixed versioned socket
  path and instructions endpoint are the discovery contract.

Primary files:

- new `Foil/AgentAccessController.swift`
- `Foil/AgentAccessServer.swift`
- `Foil/AppState.swift`
- `Foil/FoilApp.swift`
- `Foil/SettingsView.swift`
- `Foil.xcodeproj/project.pbxproj`
- new `FoilTests/AgentAccessControllerTests.swift`
- new `FoilTests/AgentAccessContractTests.swift`
- `FoilUITests/FoilUITests.swift`

Acceptance:

- Fresh install and reset-defaults states are off and create no socket.
- Enabling creates only the correct brand's socket; disabling closes a live
  connection, removes the socket, and prevents a late main-actor callback.
- Relaunch starts the service only when the persisted preference is on and only after
  the app wins the single-instance gate.
- Startup failure resets the preference to off with an actionable error and opens no
  TCP listener.
- When Foil is closed or access is off, the copied `curl` command exits nonzero within
  its documented bound. It cannot receive a structured Foil error because no server
  is running; the copied instructions explain this case.
- Every undocumented method/path/content type and every oversized or malformed
  request fails with the specified status and no state mutation.
- List/scopes/preview expose only allowed fields. Preview validates the hypothetical
  candidate set even when global local corrections are disabled.
- Seeded History, key, path, source-record, source-app, and provider secrets never
  appear in responses or diagnostics.
- The app remains responsive under slow-header, partial-body, disconnect, and 20
  concurrent-client tests.
- UI tests cover default-off, enable, starting, running, error, disable, persistence,
  copy-command, and the same-user disclosure.

### Tranche 2 — Durable proposal inbox

**Purpose:** let an agent hand bounded work to the user without granting mutation.

**Status:** 2A is implemented and acceptance-gated. 2B is implemented with local
unit, contract, integration, privacy, build, and matcher gates passing; the focused
macOS UI smoke remains pending because the local XCTest runner timed out before it
could enable automation mode. See the
[Tranche 2B evidence receipt](../evidence/agent-access-vocabulary/tranche-2b/receipt.md).

Deliver this tranche in two reviewable slices:

- **2A — durable foundation:** versioned request, proposal, snapshot, and receipt
  models; canonical payload hashing; brand-scoped atomic persistence; replay,
  conflict, queue, corruption, and simultaneous-submission tests. This slice has no
  API route or UI and therefore cannot receive a proposal in the shipping app.
- **2B — submission and review:** validation against live scopes and production
  matcher behavior; submit/status routes and OpenAPI instructions; pending count;
  review, edit, omit, reject, and discard UI; lifecycle and privacy integration
  tests.

Implementation:

- Add versioned proposal and receipt models plus an atomic proposal store under the
  brand-specific Application Support directory.
- Implement proposal submit and status routes with queue limits and canonical
  request hashing: the same request ID and payload returns the original result;
  the same ID with different content returns a conflict.
- Add a pending-proposal count, review list, details, edit, omit, reject, and discard
  actions. Receiving a proposal must not activate or focus Foil.
- Show requested scope, aliases, replacement, note, validation conflicts, synthetic
  production-engine preview, and a snapshot token covering vocabulary, rules, and
  enabled scopes at submission.
- Keep every proposal inert. Edit, omit, reject, and discard change proposal state
  only.

Primary files:

- new `Foil/VocabularyProposalModels.swift`
- new `Foil/VocabularyProposalStore.swift`
- new `Foil/VocabularyProposalReviewView.swift`
- `Foil/AgentAccessController.swift`
- `Foil/SettingsView.swift`
- new `FoilTests/VocabularyProposalStoreTests.swift`
- new `FoilTests/VocabularyProposalContractTests.swift`
- `FoilUITests/FoilUITests.swift`

Acceptance:

- Valid submission persists once and becomes visible without applying a correction.
- Duplicate request IDs return the same proposal; a reused ID with different
  canonical content returns a conflict, including under a simultaneous request race.
- Empty, oversized, over-count, duplicate-alias, ambiguous, invalid-scope,
  future-version, and malformed proposals are rejected without queue or Vocabulary
  mutation.
- Multiple proposals survive relaunch without overwriting one another.
- Reject/discard never changes Vocabulary or local rules.
- Turning Agent Access off preserves received proposals for local review but makes
  API status unavailable.
- Diagnostics contain digests, IDs, counts, timings, and result codes only; sentinel
  aliases, replacements, notes, and existing vocabulary do not appear.

### Tranche 3 — Transactional reviewed apply

**Purpose:** complete the useful workflow with one recoverable commit path for
Vocabulary metadata, linked rules, and receipts.

Implementation:

- Add a main-actor `VocabularyCorrectionCoordinator` and route current UI mutation
  methods plus agent proposal apply through it.
- Introduce `VocabularyCatalogStore` with one atomic v2 document containing
  Vocabulary correction metadata, executable rules, the global enabled flag, a
  bounded applied-proposal receipt ledger, and the legacy-source fingerprint.
- Migrate existing UserDefaults correction metadata and schema-v1 rule snapshots
  without changing IDs, timestamps, order, enabled state, case sensitivity, or
  scope. Leave the legacy sources untouched and detect post-migration legacy edits
  before using the v2 catalog again.
- Compare the proposal snapshot token before apply, then normalize and precompile the
  complete target rule set with `LocalCorrectionEngine` before any write.
- Expand grouped aliases into explicit corrections and linked rules, commit the
  catalog once, and reconcile the proposal store from the durable applied-receipt
  ledger after interruption.
- Preserve the global local-corrections switch and show when newly applied entries
  remain inactive because it is off.

Primary files:

- `Foil/LocalCorrectionStore.swift`
- `Foil/VocabularyModels.swift`
- new `Foil/VocabularyCatalogStore.swift`
- new `Foil/VocabularyCorrectionCoordinator.swift`
- `Foil/AppState.swift`
- `Foil/VocabularyProposalStore.swift`
- `Foil/VocabularyProposalReviewView.swift`
- `Foil/AgentAccessController.swift`
- `FoilTests/LocalCorrectionStoreTests.swift`
- `FoilTests/AppStateTests.swift`
- new `FoilTests/VocabularyCorrectionCoordinatorTests.swift`
- `FoilTests/VocabularyProposalContractTests.swift`
- `FoilUITests/FoilUITests.swift`

Acceptance:

- Existing corrections migrate with byte-equivalent source, replacement, scope,
  enabled, and case-sensitive fields.
- Interrupted migration, failed atomic write, stale revision, corrupt v1, and future
  schema leave legacy state untouched and surface an error.
- A previous Foil release launched after migration reads the unchanged pre-upgrade
  state. If it edits legacy state, the next current-version launch detects the
  fingerprint mismatch and enters reconciliation without overwriting the v2 or
  legacy data.
- Applying three Supabase aliases creates three visible corrections and three linked
  rules with the reviewed scope in one catalog revision.
- Apply all, selective apply, edited apply, and reject produce durable itemized
  receipts. Replaying an applied request returns the stored receipt and adds nothing.
- A concurrent UI edit creates a review conflict instead of being overwritten.
- Validation, catalog write, proposal receipt reconciliation, cancellation, abrupt
  disconnect, relaunch, and simulated crash boundaries recover without lasting
  metadata/rule divergence or duplicate apply.
- The global switch remains under user control; apply never silently enables it.
- All current Vocabulary/AppState/store tests and the 150-case matcher gate pass;
  matcher output, recording-start snapshot behavior, and performance budgets do not
  regress.

### Tranche 4 — Installed-app and release proof

**Purpose:** prove that the feature works outside XCTest and does not weaken app
packaging or privacy.

Implementation:

- Add `make test-agent-access` for deterministic unit/contract/integration coverage.
- Add `scripts/run-agent-access-installed-smoke.sh` for a signed installed Foil and
  Foil Dev build.
- Record evidence under `docs/evidence/agent-access-vocabulary/` using the repository
  acceptance-evidence format.
- Add release notes and user-facing documentation for the copied bootstrap command.

Acceptance:

- A fresh Codex task with no Foil MCP or skill runs only the copied command, reads
  instructions, lists scopes, previews, submits, and reads proposal status.
- The user reviews and applies `super base -> Supabase`; real dictation into Codex
  contains `Supabase` and History retains the original recovery text.
- Turning Agent Access off during a live connection closes it, removes artifacts,
  and produces no app-data change.
- Foil and Foil Dev can run together with separate sockets, stores, and proposals.
- `codesign --verify --deep --strict`, notarization/stapling checks, warnings-as-errors,
  full unit tests, focused UI tests, the 150-case matcher gate, and local correction
  performance gates pass.
- Diagnostics seeded with distinctive vocabulary, transcript, path, and credential
  values contain none of those values.

## Required test matrix

| Layer | Required proof |
| --- | --- |
| Pure contract | Codable round trips, normalization, stable errors, limits, idempotency, OpenAPI route parity |
| Persistence | v1 migration, atomic failures at every write boundary, corrupt/future data, stale revision, crash recovery |
| HTTP parser | fragmented reads, invalid request line/header/body, duplicate lengths, chunked body, traversal, method/content-type rejection |
| Lifecycle | default off, enable, disable, relaunch, bind failure, stale socket, symlink, wrong owner, termination cleanup |
| Privacy | seeded forbidden data absent from responses, proposal files, and diagnostics |
| Concurrency | simultaneous list/preview/propose, duplicate request race, disable during request, UI edit during review |
| UI | accessible controls and status, copy command, pending count, edit/omit/reject/apply, persistence across relaunch |
| Installed app | real Unix socket and curl, Foil/FoilDev isolation, Codex bootstrap, real reviewed correction and dictation |

## Commands expected at closeout

Focused commands should be added as the implementation lands. The final gate is:

```sh
make test-agent-access
make test-local-correction-engine
make test-local-correction-performance
make build-warnings-as-errors
make test
```

Run focused Agent Access XCUITests in the active desktop session, then run the
installed-app smoke against signed Foil and Foil Dev builds. Record any skipped
hardware or desktop checks as residual risk; do not count them as passes.

## Review boundaries

Keep each PR within one tranche. The reviewer should reject scope that adds MCP,
fuzzy matching, project awareness, History access, or unattended apply before the
installed proposal workflow is proven. Any change to matcher semantics requires a
separate corpus, false-positive budget, and performance review.
