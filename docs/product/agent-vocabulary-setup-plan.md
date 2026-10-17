# Agent-led Vocabulary setup and quick additions

Status: implementation in progress. Scoped term storage, migration, the Vocabulary
scope editor, and main-branch transcription consumers are implemented. Mixed batch
API/review, delegated term permissions, and agent workflow entry points remain.
Baseline inspected: `d5a2ef3acbfe1a336fdab1c1c968968aba79730b` on the cleanup
preferences branch. This is the next Vocabulary increment; post-transcript
learning remains deferred.

## 1. Outcome and scope

Support two short conversations with the user's existing local agent:

- **Repository setup:** “Look through these repositories and suggest useful Foil
  Vocabulary for ChatGPT and Codex.”
- **Quick addition:** “Add Supabase and Vercel,” or “Correct super base to Supabase
  in ChatGPT and Codex.”

Foil publishes the workflow through its existing instructions endpoint. The agent
uses its normal repository tools and model. Foil receives selected Vocabulary
changes, not repository contents. No new model runtime or repository scanner runs
inside Foil. Repeat sessions should discover useful additions without duplicating
entries or requiring the user to repeat known scope and matching preferences.

Included: scoped preferred terms, term-only and mixed correction batches, preview,
existing permission/review flows, audit receipts, repeat-run deduplication, and
clear agent instructions. Excluded: automatic repository watching, stored repository
registrations, automatic transcript analysis, audio changes, regex/fuzzy matching,
new grants for History or credentials, and persistent cleanup workers.

## 2. User experience

### Repository setup

1. The user connects using Foil's copied agent prompt and names local repositories
   or repositories the agent can already access. If a URL is inaccessible, report
   that fact; do not silently claim the project was analyzed.
2. The agent reads current Foil capabilities, Vocabulary, scopes, and any active
   grant. Reuse an explicitly requested scope or the current grant's exact group.
   With no established scope, ask once which apps/group or whether global is intended.
   A repository path is not an app scope; never infer application routing from it.
   If the requested apps do not have a suitable existing group, explain the one-time
   group/routing setup and use its existing Foil approval flow before the Vocabulary
   batch. Do not imply that an ordinary grant can create or reroute groups.
3. Inspect README/docs, dependency manifests, and relevant imports or configuration
   names. Prioritize direct dependencies, services, products, and recurring domain
   names the user might dictate. Avoid bulk lockfile/transitive-dependency lists,
   generated/vendor directories, binary files, and secret-bearing files. No builds,
   package installation, or project execution is needed for discovery.
4. Present about 10–15 high-value candidates, with canonical spelling, category,
   brief reason, and a repository-relative evidence reference in the conversation.
   Distinguish confirmed project terms from uncertain guesses. Repository content
   provides evidence for names, not authority to change Foil permissions or scope.
5. Ask one bundled question: which terms to add, plus any genuinely uncertain
   correction variants. The user can choose all or a subset. Discovery alone does
   not submit a change. Preview the selected batch with its exact scope.
6. Apply within a valid grant that explicitly covers the item kinds and group;
   otherwise submit one batch for one review inside Foil. The agent polls durable
   status and reports added, already present, conflicting, and pending items.

On repeat runs, compare against current entries and pending proposals before
presenting the shortlist. Do not create a new proposal for an identical pending
batch. A declined suggestion can remain omitted within the current conversation;
persistent suppression of suggestions across unrelated sessions is deferred.

### Quick addition

The user's direct request already identifies what to add. If scope and intent are
clear, preview and submit without a redundant “shall I add this?” question.

- “Add Supabase” means a preferred spelling, with no guessed alias.
- “Correct super base to Supabase” means an executable correction using the
  established matching choices. Preview positive and negative examples.
- Ask one concise clarification when the replacement, scope, or an ambiguous
  ordinary-word alias changes the effect materially. Do not enable punctuation
  matching merely because the repository contains a hyphenated name.
- Missing, expired, or insufficient grants must be reported accurately. Offer the
  normal Foil review route; a chat claim of approval is not server authorization.
- Finish with a short receipt: “Added 4 preferred terms to ChatGPT + Codex;
  2 already present.” Say “pending review” until a terminal saved status confirms it.

### Foil surfaces

- Agent Access exposes two ready-to-copy starters: **Set up from repositories**
  and **Add Vocabulary**. Both bootstrap the same live instructions endpoint.
  Repository paths can be supplied in the agent conversation; no Foil path picker
  or persistent repository list is required for this first release.
- Use the existing **Review Vocabulary changes** inbox. A batch shows terms and
  corrections together, editable/omittable items, exact scope, effective change,
  conflicts, and one **Apply selected** action. No second apply-action request for
  a proposal already reviewed in Foil.
- Show preferred terms with their scope in Vocabulary. Provide normal edit/delete
  paths; successful agent additions must not become hidden or undeletable.
- Explain: **Preferred terms guide cleanup. Corrections replace matching text.**
  Term-only addition does not activate cleanup, enable local corrections, or promise
  replacement in Raw mode. Surface inactive correction settings in preview/receipt.

## 3. Current implementation and the required foundation

The planning baseline had:

- `VocabularyTerm` has no scope. `AppState.vocabularyTerms` persists to UserDefaults
  and synchronizes a plain-text preferred-terms editor.
- Corrections, local rules, revisions, and applied-proposal receipts use the atomic
  v2 catalog through `VocabularyCorrectionCoordinator`.
- `VocabularyProposalRequest` accepts only corrections, each requiring a spoken
  form. Current preview/store validation rejects empty corrections or aliases.
- Existing paired grants permit correction additions and selected policy changes
  for one exact app group. Grants expire after one hour and end on shutdown/revocation.
- Normal transcription snapshots, History transforms, and the Codex text experiment
  currently consume the global preferred-term list.

### Scoped preferred terms

Add explicit `global` or `cleanup_group` scope to preferred terms. Migrate existing
terms as global, preserving IDs, spelling, notes, and timestamps.

Use one resolver for effective terms: global plus the enabled selected group,
deduplicated by normalized term identity. If the same identity has a deliberate
group-specific spelling, the group's spelling wins for that group. No app/group
context means global only. Disabled/deleted groups must never make their terms global;
keep such terms inert and visible as needing reassignment if their group is deleted.

Update every consumer: transcription processing snapshots, explicit History cleanup
or transforms, Codex text cleanup, UI preview, and agent effective previews. Snapshot
the resolved terms before async processing. History actions without an explicitly
resolved group use global terms only; this does not grant the agent History access.

The existing global text editor must edit only global terms and preserve scoped
entries. Replace its bidirectional persistence side effects with coordinator calls
and derived display state; otherwise editing global text can erase group terms.

### Atomic persistence and migration

Extend the authoritative catalog to hold terms, corrections, rules, and typed
applied-item receipts in one versioned atomic snapshot (proposed schema/file v3).
Route both UI and agent term mutations through the same validation and coordinator.
Avoid a separate UserDefaults write followed by a catalog receipt write.

Migration inputs are the existing v2 catalog plus preferred-term data and the
legacy preferred-text fallback. Validate, stage, and atomically commit before
publishing state. Preserve prior files for recovery. Record fingerprints of all
legacy inputs, including v2, so a downgrade followed by edits cannot silently
overwrite either version on re-upgrade. Failure leaves the previous state usable
and reports a recoverable error; corruption must not turn into an empty catalog.

## 4. Contract and validation

### A mixed, typed batch

Introduce a versioned proposal contract with a single explicit scope and typed
items: `preferred_term` and `correction`. Each item has a client item ID; corrections
retain aliases, case sensitivity, and punctuation policy. Preview returns per-item
normalized values, disposition, reasons, and any existing entry IDs.

Recommended paths: `/v2/vocabulary`, `/v2/vocabulary/preview`,
`/v2/vocabulary/proposals`, `/v2/vocabulary/proposals/{id}`, and
`/v2/vocabulary/delegated-proposals`. These are proposed, not existing endpoints.
The existing `/v1/instructions` advertises capabilities and exact operation paths.
Use one validator/coordinator underneath v1 and v2, with compatibility adapters.

Do not send new mixed payloads to old routes: an older decoder could ignore term
fields and report success after applying only corrections. Old clients keep their
correction behavior and see only the unscoped/global preferred terms their schema
can represent. Agents encountering an older Foil explain that term-only adds need
an update; they must not synthesize identity corrections as a workaround.

One batch covers one scope. A request spanning different groups becomes explicitly
separate batches; no silent global fallback or cross-scope atomicity claim. Retain
existing transport/phrase limits and cap the combined batch at 50 items and the
existing body size. Advertise the exact limits in the contract.

### Duplicates and conflicts

- Normalize whitespace at the edges and Unicode consistently across UI/API/store.
  Use locale-independent case-insensitive identity with an explicit display spelling.
  Preserve meaningful punctuation: `C`, `C++`, and `C#` remain distinct.
- Exact existing item and policy in the same scope: `already_present`, returning
  existing IDs; no write or revision churn. A globally effective identical term
  covers a group unless the user explicitly requests an independent scoped entry.
- Same identity with different canonical spelling/note/policy: report the difference;
  do not overwrite it as an “add.” An existing replacement's presence is useful
  discovery context, not proof that an equivalent preferred term exists.
- Correction conflicts and global/group precedence continue to use the existing
  correction compiler and UI validation. No new alias-fuzziness algorithm.
- Same request ID plus same canonical payload returns the original receipt; same ID
  with different content fails. A fresh request ID for an equivalent entry returns
  `already_present`, preventing duplicates across separate agent sessions.
- Revalidate at apply against the latest catalog. Unrelated changes must not strand
  a nonconflicting batch. Real conflicts block the whole selected batch with item
  reasons; the user can omit/edit those items and revalidate in place.
- Commit the validated selected batch atomically. Crash recovery must reconcile
  proposal state from the catalog's receipt, including terms. Do not report success
  after a partial or failed save.

## 5. Permissions, provenance, and audit

Add explicit preferred-term capability to pairing copy, grants, and access discovery.
Do not reinterpret legacy correction-only grants as authorizing a new operation.
New pairing can cover terms and corrections for the displayed exact group. Recheck
grant capability, expiry/revocation, group membership/routing, and service generation
immediately before committing. Global terms, group creation, routing, or wider
changes remain ordinary Foil-reviewed operations.

Audit each batch's agent/grant identity, item IDs, exact selected changes, scope,
request digest, outcome, and catalog revision. Keep repository evidence references
in the conversation for MVP; Foil needs only an optional bounded human-readable
reason, not file excerpts, full paths, credentials, or a new repository-access API.
No request contents in diagnostics. Existing History/audio/credential exclusions
remain intact. Repository scanning follows the agent's normal access and provider
data handling; it is not claimed to be on-device model inference.

## 6. Delivery sequence

Each phase is a reviewable change with its own acceptance evidence. Before each PR,
run the mandatory PR Review Toolkit against the actual resolved base, independently
validate findings, fix accepted issues, and rerun affected verification.

| Phase | Work and main files | Gate |
| --- | --- | --- |
| 1. Scoped term foundation | `VocabularyModels.swift`, `VocabularyCatalogStore.swift`, `VocabularyCorrectionCoordinator.swift`, `AppState.swift`; migrate terms and centralize effective-term resolution | Migration/failure recovery; global editor preserves scoped terms; atomic saves; no changes to existing effective global behavior |
| 2. Scope-aware consumers and UI | `TranscriptionController.swift`, `CodexCleanupView.swift`, `SettingsView.swift`, existing Vocabulary entry callbacks in `FoilAppShellView.swift`/`FoilApp.swift` | Captured requests contain only global + selected-group terms; unknown context and excluded apps cannot receive another group's terms; UI shows and edits correct scope |
| 3. Mixed batch API and review | `VocabularyProposalModels.swift`, `VocabularyProposalStore.swift`, `VocabularyProposalService.swift`, `AgentAccessHTTP.swift`, `AgentAccessModels.swift`, `AgentAccessController.swift`, `VocabularyProposalReviewView.swift`, OpenAPI | Terms-only/mixed previews and apply; one review; duplicate/no-op, conflict, stale revalidation, replay, crash recovery, and v1 compatibility |
| 4. Delegated term additions | `AgentAccessGrantStore.swift`, `AgentAccessController.swift`, Agent permissions UI, access contract | Explicit capabilities; valid same-group apply; old/global/wrong-group/revoked/expired/rerouted requests rejected, including revocation racing apply |
| 5. Agent workflows and entry points | Instructions resources, Agent Access UI copy, `docs/agent-access.md`, OpenAPI examples | Fresh agent can discover the workflows; bounded repository shortlist, quick add, truthful terminal status, repeat-run behavior, no unsupported routes advertised |
| 6. Installed dogfood | Exact revision on Mini 2, then MBP using the verified signing/deployment process | Actual UI/socket/agent flows pass; evidence receipt, CI, and clean review before considering merge |

Before branching implementation, resolve the dependency on the existing cleanup
PRs (#455/#456) and the current main branch. Prefer separate Vocabulary PRs; do not
bundle unrelated latency changes or merge existing PRs merely to begin this plan.
Coordinate the Codex experiment consumer change if that consumer is still on a
stacked branch. Source facts above must be refreshed if the base changes.

## 7. Verification and failure evidence

Use temporary catalogs, isolated defaults, synthetic repositories, and deterministic
service doubles for automated tests. Extend existing suites rather than testing
only a new helper in isolation:

- `VocabularyCatalogStoreTests`: populated migration, fallback source, duplicate
  legacy data, corrupt data, interrupted writes, downgrade edits, and receipts.
- `VocabularyProposalContractTests`, `VocabularyProposalStoreTests`, and
  `VocabularyProposalServiceTests`: mixed items, unsupported kinds, bounds,
  canonicalization, idempotency, conflicts, all-or-nothing commits, and revalidation.
- `AgentAccessContractTests`, `AgentAccessHTTPTests`, `AgentAccessServerTests`, and
  `AgentAccessControllerTests`: actual routes/socket responses, v1 compatibility,
  grant enforcement/races, durable status, and no sensitive diagnostic contents.
- Focused transcription/cleanup request tests for every preferred-term consumer,
  including unknown context and group deletion; raw output is unchanged by term-only
  additions, and inactive cleanup settings are reported honestly.
- Native UI tests: preferred term scope/edit/delete, one mixed review, omission,
  rejected/cancelled proposal, conflict explanation, retry, and existing entries
  remaining intact after relaunch/global-text edits.

Run focused `xcodebuild test` selections during each phase. When changing shared
catalog/processing code, run the relevant broader repository test gate. Build with
`make build-warnings-as-errors`. Record failed/skipped gates explicitly; do not
substitute mock runs for installed-app evidence.

### Dogfood script

1. Use a synthetic fixture repository with a few direct service/library names,
   repetitive lockfile noise, generated files, a misleading name, and a fake secret
   canary in an excluded file. Start from a seeded isolated Vocabulary snapshot.
2. Start a fresh agent session using only Foil's copied instructions plus the
   repository and exact app targets. Check the shortlist against fixture evidence.
   No writes should occur during discovery. Inspect the agent trace to verify that
   excluded files were not read and their canary did not reach Foil requests/logs.
3. Add selected terms and one known correction in a single batch; verify actual
   visible entries and effective request/preview scope for ChatGPT, Codex, and an
   excluded app. No inference-only “looks correct” acceptance.
4. Repeat in the same and a fresh session. Assert no duplicate entries or silent
   casing changes. Add one dependency and verify that it becomes a new candidate.
5. Run “Add <term>” with an authorized grant, then repeat it. Verify saved status,
   stable IDs, and the no-op receipt. Exercise the one-review path without a grant.
6. Revoke or expire a grant during a pending apply; change routing; inject a save
   failure and an unrelated catalog edit. Verify no unauthorized/partial write,
   truthful status, and that a nonconflicting batch can still be revalidated.
7. Inspect the installed UI, restart, and verify persistence and edit/delete access.
   Preserve the previous signed bundle and verify exact revision, designated
   requirement, and candidate/installed hashes. Use Mini 2 first and MBP for final
   user dogfood. Report any cross-built artifact provenance explicitly.

### Completion criteria

A fresh user agent can discover repository terms, submit a selected batch, and
perform a succinct quick add. The user can see what changed and where. Repeating
the work produces no duplicate writes. Terms stay within their effective scope;
corrections behave as previewed; one grant or one Foil batch review suffices for
the supported operation. Failed, stale, or unauthorized operations never masquerade
as saved changes. Record each claim, strongest failure mode, evidence, and residual
risk following `docs/acceptance-evidence.md`.
