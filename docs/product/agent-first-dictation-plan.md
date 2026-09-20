# Agent-first dictation: implementation and acceptance plan

Date: 2026-09-14
Status: proposed implementation plan; no feature implementation or test results claimed.

Tranche 0 execution now has a frozen [matching contract and test harness](../../tests/fixtures/local-corrections/contract.md).
Use that contract for the concrete v1 Unicode and protected-span decisions below.

## Outcome and recommended first milestone

Let people teach Foil terminology through their coding agent, then apply those
lessons locally during dictation without a model round trip. Preserve the user's
words, scope corrections predictably, and retain a recovery path when processing
or delivery fails.

First milestone: **Tranches 0–1, opt-in local phrase corrections in the Mac app.**
Second milestone: **Tranches 2–3, teach Foil from Codex or Claude Code.**
Project packs and agent cleanup follow behind their own evidence gates. A later
tranche must not delay shipping an independently useful earlier milestone.

This document plans the work. It does not authorize a release, start an autonomous
goal, create external issues, or claim the product has these capabilities.

## Current implementation facts

Inspected in the local checkout on 2026-09-14:

- [VocabularyModels.swift](../../Foil/VocabularyModels.swift) stores written-as /
  correct-version pairs and preferred terms, including optional source metadata.
- [TranscriptionService.swift](../../Foil/TranscriptionService.swift),
  `TranscriptCleanupRequest.systemInstruction`, adds vocabulary to model prompts.
- [TranscriptionController.swift](../../Foil/TranscriptionController.swift),
  `processTranscriptOrRaw`, returns raw text before requesting cleanup. Fresh
  transcription, audio retry, and History transforms are separate paths to cover.
- [TranscriptProcessingMode.swift](../../Foil/TranscriptProcessingMode.swift)
  exposes raw and cleanup modes; raw explicitly promises the transcription output.
- [CleanupGroup.swift](../../Foil/CleanupGroup.swift) scopes cleanup by app identity;
  it does not identify a repository or an agent conversation.
- [TranscriptionHistory.swift](../../Foil/TranscriptionHistory.swift) stores final
  successful text, with a separate in-memory recovery path when persistence is off.
  Existing tests explicitly check final-only storage.
- [HistoryPopoverView.swift](../../Foil/HistoryPopoverView.swift) already supports
  saving vocabulary from a transcript selection and saving then re-cleaning.
- [LocalPairingBridge.swift](../../Foil/LocalPairingBridge.swift) serves a separate
  iPhone/Mac bridge concern. Its network scope must not silently become a rules API.

Existing code is a foundation, not evidence that the proposed behavior works.

## Product and processing contract

### Choices and compatibility

1. **Verbatim:** preserve raw behavior exactly; no local corrections or cleanup.
2. **Quick corrections:** apply explicitly enabled local phrase rules; no cleanup
   provider call. The transcription route remains the user's existing selection.
3. **Cleanup profile:** preserve existing model cleanup; local rules can be enabled
   separately. Agent-backed cleanup is a later optional provider.

All existing users retain their behavior on upgrade. Existing vocabulary remains
model guidance until the user explicitly promotes selected pairs to local rules.
No global starter replacements are silently enabled. In particular, `the cell`
and `codecs` must not become global defaults.

Internally, keep local-rule selection independent of cleanup-provider selection;
do not make every combination a new processing enum case. Snapshot the target,
resolved group, rule revision, and processing settings at recording start. Group
or rule changes during an in-flight recording take effect on the next recording.
For file transcription, snapshot at submission. Audio retry uses the original
target context where available and an explicitly resolved current rule revision;
missing original context must not substitute the newly focused app silently.

Pipeline: raw transcript -> local rules when enabled -> model cleanup when enabled
-> one final delivery. Rules run once on the raw input, never recursively over
replacement text. Model failure returns the successful locally corrected text,
or raw text when rules were off, with an accurate fallback indication. Rule-engine
failure returns raw text with a visible failure indication. Verbatim bypasses both.
Practice dictation keeps its existing provider-practice behavior and gains no
hidden corrections, History writes, or agent calls.

### Rule semantics, fixed before coding

- V1 supports literal phrases, exact replacement text, and explicit sensitive or
  insensitive case matching. Replacement preserves the configured capitalization.
- Match at Unicode letter/number/combining-mark/underscore boundaries; whitespace
  is literal in v1. Use NFC canonical equivalence and ASCII-only case folding in
  v1, with an original-offset map. Preserve the bytes of every untouched span.
- Select leftmost matches; for candidates starting at the same position, prefer
  more specific scope, then longest phrase, then stable rule ID. Reject identical
  normalized source/scope pairs with conflicting replacements at write time.
- Never rescan replacement output. `A -> B` plus `B -> C` changes original `A` to
  `B`, not `C`. Do not claim all rule sets are mathematically idempotent; enforce
  exactly one application per processing operation instead.
- Preserve fenced code, inline backtick code, and recognized URLs in v1. Test the
  protected-span recognizer, including malformed delimiters. Plain identifiers
  are protected by boundary matching, not by guessed programming-language syntax.
- Initial supported envelope: 1,000 enabled rules, 64 KiB UTF-8 transcript input,
  256 Unicode scalars per source/replacement phrase. Oversize rules are rejected;
  oversize transcript processing falls back intact with a visible explanation.
  These limits are frozen in the Tranche 0 contract before implementation.
- Raw text and final text are distinct values throughout processing. Paste Last
  and Copy use the chosen final result; an explicit original-text recovery action
  uses raw text and never attempts to silently undo text in another application.
- Original-text recovery is in-memory for the latest session in Tranche 1, bounded
  and cleared on Clear History/quit. Persisting both forms in History is deferred;
  no automatic expansion of stored transcript data or retrospective rewriting.

## Tranche map

| Tranche | Deliverable | Dependency | Suggested PR boundaries |
| --- | --- | --- | --- |
| 0 | Fixed semantics, adversarial corpus, baseline and benchmark harness | None | One test/contract PR |
| 1 | Usable local corrections, group scope, recovery | 0 | Engine/store; app integration/UI |
| 2 | Versioned local rule-management service and CLI | 1 | Service/CLI plus contract tests |
| 3 | Agent teaching through MCP and a documented workflow | 2 | MCP adapter/workflow plus live client proof |
| 4 | Explicit project packs and project activation | 3 | Import/activation; agent-generated packs |
| 5A | Agent-cleanup feasibility experiment and decision | 1; after 3 preferred | Bounded experiment/report |
| 5B | Optional agent cleanup provider if 5A passes | 5A | One provider at a time |

PR boundaries are review units, not instructions to ship incomplete UI. Each
tranche needs a working vertical demonstration and the negative cases below.

## Tranche 0 — establish the oracle

**Claim:** we can detect helpful corrections, harmful replacements, latency
regressions, and failures to deliver the intended text before expanding scope.

Create a versioned synthetic corpus under the proposed directory
`tests/fixtures/local-corrections/`. Each fixture contains raw text, active scope,
rules, expected exact output, and the reason an example should or should not match.
Use at least 120 reviewed fixtures: 40 positive, 60 negative/ambiguous/protected,
and 20 overlap/Unicode/boundary cases. Keep at least 30 separately authored cases
held out from implementation tuning; a final reviewer checks their expectations.
Fixture counts supplement coverage; they do not prove correctness by themselves.

Required cases include all four user examples; literal discussion of audio codecs;
"put it in the cell"; "cloud code runs remotely"; punctuation; plurals; mixed case;
emoji; combining marks; non-Latin neighbors; URLs; identifiers; repeated phrases;
replacement metacharacters; overlapping phrases; cycles; and unchanged empty input.
Each ambiguous positive must identify the explicit rule/scope that makes it valid.
Do not imply an unconditional literal rule understands semantics within its scope.

**Acceptance and proof:**

- Capture baseline behavior for raw, cleanup success/failure, retry, History off,
  and cross-app delivery from the existing tests and a dedicated dev-app run.
- Run current relevant suites once; record failures as baseline findings with
  owners. A pre-existing failure affecting this pipeline blocks its gate until
  explained or fixed; unrelated failures remain disclosed, never relabeled green.
- Add a harness that fails for deliberately injected defects: unbounded substring
  matching, disabled-scope application, and recursive replacement. The tests must
  demonstrably catch all three defects before relying on their passing results.
- Measure processing separately from transcription/network/paste. Proposed local
  budget: p95 <= 10 ms and p99 <= 25 ms for 500 rules and a 10 KiB input; <= 100 ms
  p99 at the supported maximum. Include 50 cold compilations and 1,000 warmed
  operations, a fixed seed, Release build, hardware/OS, and full timing samples.
  Record compile/load costs separately. Validate on Apple Silicon and Intel before
  claiming the budget across both; missing hardware limits the claim explicitly.
- Freeze numeric targets and corpus before feature tuning. If baseline establishes
  a target is impractical, record the measured reason and revise it visibly before
  proceeding, not after a failing implementation benchmark.

**Strongest failure:** tests merely restate the algorithm or benchmark bypasses
the real pipeline. Proof must include independently expected strings, injected
defect failures, and a controller-level timing boundary.

## Tranche 1 — local corrections people can use

**Scope:** phrase engine; validated atomic persistence; global and Cleanup Group
scope; create/edit/disable/delete; preview; opt-in promotion of existing pairs;
integration with transcription and recovery. No regex, agent access, or projects.
Likely touch points: vocabulary models, AppState, CleanupGroup, transcription
controller, History and vocabulary UI, and their existing test suites.

**Acceptance criteria:**

- T1.1: All reviewed and held-out deterministic corpus cases pass exact comparison;
  10,000 seeded generated cases establish determinism, no matches outside scope,
  bounded output, and byte preservation outside replacement spans. Failing seeds
  become permanent regression fixtures.
- T1.2: Existing raw and cleanup settings survive upgrade/relaunch unchanged.
  Re-running migration produces no duplicates; corrupt or future-version rule
  data never silently enables rules or overwrites the unreadable source file.
- T1.3: A local-only correction run makes zero cleanup/agent requests, proven with
  rejecting service spies and an app fixture-server request log. With local
  transcription selected, the demonstrated path needs no external network.
- T1.4: Switching apps or editing rules while transcription is delayed does not
  change the captured target/scope/revision. Deleting a group mid-flight preserves
  that snapshot for the pending operation, then resolves safely for the next.
- T1.5: Engine failure, oversize input, model failure, cancellation, and duplicate
  callbacks cannot lose a successful transcript or cause two deliveries. History
  off writes no new transcript content; clear/quit clears new recovery state too.
- T1.6: Preview and actual execution use the same engine/revision and agree.
  Disabled rules stop applying; deletion and undo survive relaunch appropriately.
  Re-clean uses an explicit input choice; it cannot accidentally run phrase rules
  again on an already corrected final transcript. Paste Last is delivery only.
- T1.7: UI exposes active scope, enable state, validation errors, original recovery,
  and persistence failures with keyboard-accessible controls and stable test IDs.
- T1.8: Meet Tranche 0 timing budgets. Normal and worst-case inputs keep the main
  UI responsive; include an interaction trace during maximum-size processing.

**Required proof:** focused model/controller/persistence tests; fixture-server
integration; upgrade fixtures from current serialized data; fault injection for
write failure and interrupted save; XCUITest screenshots plus resulting state;
real insertion into TextEdit and one installed coding-agent text composer. Read
back actual target text, verify the other target is unchanged, and preserve a
sanitized recording/receipt. A posted paste command is insufficient.

**Exit demo:** enable `super base -> Supabase` for an agent group, dictate and
observe exact inserted text, switch to an unassigned app and observe no correction,
then recover the original and disable the rule. Demonstrate no cleanup request.

**Rollback:** disable local rules without touching existing vocabulary or provider
settings. Keep additive storage compatible; test the documented downgrade path
against the previous app before release, including retention of the new data.

## Tranche 2 — a local interface agents can safely call

**Scope:** one versioned service used by both UI and a proposed `foil rules` CLI.
Choose a local Unix-domain socket with owner-only permissions and same-user peer
validation; no TCP listener or reuse of the iPhone bridge. CLI payloads travel via
stdin/stdout, not shell-interpolated commands. Packaging/signing the helper is part
of this tranche. Same-user local processes share this access boundary; do not claim
per-agent isolation from filesystem permissions alone.

Proposed operations: list, validate, preview, propose batch, apply batch, rollback.
Responses include schema version, opaque request ID, revision, changed rule IDs,
and structured errors. Mutations require expected revision and idempotency key.
One atomic batch either applies completely or leaves the prior revision intact.
The app owns serialization; the CLI never writes preferences directly.

Default integration mode is proposals: the user reviews a concrete rules diff in
Foil. An explicit agent-managed scope grant permits future writes within that
scope without repeated dialogs. Revocation takes effect on the next mutation.
Bind grants to app-issued client credentials, stored outside repositories and
redacted from logs. Verify the grant again at commit time, including after a queued
request waits. This controls configured clients; it does not isolate malicious
processes already running with the same user's full filesystem access.
This is proposed product behavior, not a request for approval during this planning
task. Rules access grants no History, audio, keychain, or paste capability.

**Acceptance criteria and proof:**

- T2.1: Contract tests cover every operation plus malformed JSON, unsupported
  versions, unknown fields, duplicate IDs, empty/oversize payloads, invalid scopes,
  stale revisions, request replay, and conflicting concurrent edits.
- T2.2: Replay of an identical successful mutation returns the same receipt;
  reuse of its key with different content fails. Lost responses and process
  restarts never create duplicate rules or partially applied batches.
- T2.3: App offline, helper mismatch, revoked grant, read-only client, permission
  failure, and socket replacement produce actionable errors and no mutation.
  Verify listener/socket ownership directly and attempt unauthorized operations.
- T2.4: A UI edit racing an agent update causes a visible revision conflict;
  rollback also checks revision and cannot erase a later unrelated edit.
- T2.5: Shell metacharacters in phrases remain literal data. Sentinel transcripts,
  credentials, private paths, and rule text never appear in normal diagnostics.
  Preview returns only caller-supplied test text; it does not retrieve History.
- T2.6: Run the installed, signed helper against Foil Dev from an external process,
  then relaunch Foil and verify exact persisted state through the UI. No mocks for
  this packaging/integration gate. Production and Dev stores remain isolated.

**Exit demo:** propose, inspect, apply, preview, replay, provoke a stale-write
conflict, and rollback a rule through the CLI, observing the corresponding UI.
**Rollback:** disable the local integration; existing app-managed rules still work.

## Tranche 3 — teach Foil from the user's agent

**Scope:** a thin stdio MCP adapter over Tranche 2, with documented agent workflow.
The agent uses context already available in its conversation; Foil does not scrape
Codex/Claude databases or automatically ingest conversation history. A subagent
is optional client behavior, not required for correctness or every dictation.

**Acceptance criteria and proof:**

- T3.1: Tool discovery and schemas map exactly to supported operations and grants.
  Protocol tests cover disconnect/reconnect, timeout, retry and structured errors.
- T3.2: In each client advertised as supported, a real session can propose and test
  `super base -> Supabase`, apply it within the chosen grant, and confirm the next
  Foil dictation reflects it. Save a sanitized tool transcript, rule revision, and
  observed target text. A CLI-only test does not prove MCP/client compatibility.
- T3.3: Repeat identical scripted workflows five times per supported client:
  explicit new rule, duplicate request, conflicting rule, ambiguous global rule,
  and rollback. All service invariants must hold; disclose agent proposal failures
  separately. Do not count agent prose saying “saved” as a successful mutation.
- T3.4: Prompt-injection text embedded in examples cannot bypass service scopes,
  enable History access, execute commands through the rules interface, or mutate
  without its required grant. Reject bad tool requests regardless of model output.
- T3.5: Connection failure leaves ordinary dictation and existing rules available.
  No MCP process is needed in the per-dictation correction path.

**Exit demo:** “Teach Foil the terms we keep correcting in this conversation,”
followed by review/activation, observed dictation, and successful rollback.
**Release gate:** claim only clients actually exercised. One working client can
ship first; list the other as unverified until its live acceptance run succeeds.

## Tranche 4 — explicit project vocabulary packs

**Scope:** proposed versioned `.foil.json` packs, import/export, project selection,
and agent-assisted generation from a user-selected repository. Start with manual
activation or an explicit client context handshake. App name, window title, or an
agent's current working directory elsewhere is not reliable project detection.

**Acceptance criteria and proof:**

- T4.1: Project activation is visible. Unknown/expired context applies no project
  rules. Switching between two repositories in one agent app is demonstrated;
  delayed transcripts keep the project captured at recording start.
- T4.2: Scope precedence is project > group > global for candidates at the same
  position, followed by the existing length/ID rules. Collision previews identify
  shadowed rules. Test all combinations with the same input phrase.
- T4.3: Imported packs are inert data until activated. Import does not execute
  scripts, follow remote references, read arbitrary paths, or enable new providers.
  Malformed/future-version packs, symlinks, and repository changes get explicit
  handling. V1 imports a reviewed snapshot; file changes require re-import.
- T4.4: Round-trip export/import preserves semantics and excludes transcripts,
  credentials, absolute local paths, and source-record identifiers. Re-import is
  deduplicated and undoable. Two worktrees have explicit identities rather than
  silently sharing active scope.
- T4.5: Generated suggestions include positive/negative examples. Dependency names
  alone do not justify enabling ambiguous aliases. Test a video project where
  `codecs` stays unchanged and an explicitly configured Codex project where it
  changes; also show a within-project ambiguity that requires disabling the rule.

**Exit demo:** two projects in the same agent app, distinct vocabulary behavior,
clean exported pack, changed pack requiring review, and project deactivation.
**Rollback:** deactivate project rules while preserving global/group settings.

## Tranche 5A — agent-cleanup experiment

**Question:** does a separate agent-backed cleanup session materially improve
technical dictation enough to justify its latency, authentication, and maintenance?

Investigate Codex app-server first; assess Claude independently. Current reference
points from the preceding research are [Codex app-server](https://learn.chatgpt.com/docs/app-server)
and [Claude Agent SDK](https://code.claude.com/docs/en/agent-sdk). Recheck current
supported authentication and distribution terms during this tranche. Do not assume
an installed subscription permits a third-party cleanup provider or that starting
a server gives access to the user's active conversation.

Create a separate narrowly configured session; no work in the user's active task,
no action tools, inherited MCP tools, repository instructions, or ambient project
access. Prove these restrictions at the protocol boundary. Inability to enforce
them blocks this provider. Launch/configuration must avoid shell interpolation.

**Experiment and decision criteria:**

- Use 60 reviewed technical prompts, with a separate holdout subset, each run three
  times per candidate route. Include negation, uncertainty, numbers, service names,
  file paths, explicit constraints, corrections, long speech, and instruction-like
  text. Include user-approved natural recordings as well as synthetic fixtures;
  synthetic speech alone cannot establish real dictation quality.
- Compare verbatim, local rules, existing cleanup, and candidate agent cleanup on
  the same raw input. Measure retained facts/constraints, harmful edits, useful
  structure, extra words, failure rate, and p50/p95/p99 added latency. Record model,
  configuration, authentication route, versions, cold/warm state, and usage where
  the provider exposes it. Never assume a cleanup call has no usage cost.
- Hard gate: zero observed critical intent changes across all repeats: negations,
  constraints, names, numbers, or invented actions. Use deterministic checks plus
  human review of every output; a model judge is supplementary. Report this as
  observed corpus performance, never a guarantee for arbitrary speech.
- Proposed usefulness gate: on at least 80% of the subset explicitly needing
  restructuring, reviewers find improved clarity without loss of content, and the
  candidate improves on existing cleanup by at least 10 percentage points. Freeze
  the rubric before running. If the benefit is only setup convenience, name and
  test that different justification explicitly before implementation.
- Proposed automatic-cleanup gate: warm p95 added latency <= 2 seconds for inputs
  up to 200 words, with a 3-second hard deadline. Report cold runs separately; cold
  startup is included in the deadline. If quality passes but latency fails, evaluate
  only an explicit “Refine” action; do not silently weaken the fast-dictation gate.
- Test missing installation, expired auth, quota exhaustion, crash, refusal,
  malformed/empty/oversize output, timeout, cancellation and late success after
  fallback. None may block recovery or trigger a second paste.

**Deliverable:** reproducible report and go/no-go decision, including actual costs
and limitations. A no-go is successful completion of the experiment, not successful
delivery of an agent-cleanup feature.

## Tranche 5B — optional agent cleanup, conditional on 5A

Implement only provider(s) that passed 5A. Add visible routing/setup, deadline and
cancellation, per-group opt-in, exact-once output selection, in-memory original
recovery, and a kill switch back to local corrections. Surface failure honestly.

**Acceptance:** rerun the full 5A corpus against the packaged app integration;
prove forbidden tools are unavailable, no active user conversation is modified,
no unconfigured provider receives text, and every error case preserves recovery.
History off and redacted diagnostics must still pass with sentinel data. Run real
target insertion and cross-app focus-change cases under delayed provider responses.
Keep all unmeasured providers and subscription claims out of release copy.

## Verification commands and evidence policy

Follow [acceptance-evidence.md](../acceptance-evidence.md). These commands exist
today; new suites named by the implementation must be added before citing them as
evidence. Do not mistake this list for a claim they were run for this planning edit.

Focused baseline example (use a unique result-bundle path on each execution):

```sh
RUN_LIVE_GROQ_TESTS=0 xcodebuild test -scheme Foil -configuration Debug \
  -destination 'platform=macOS' \
  -only-testing:FoilTests/TranscriptionControllerTests \
  -only-testing:FoilTests/TranscriptionHistoryTests \
  -only-testing:FoilTests/AppStateTests \
  -only-testing:FoilTests/CleanupGroupTests \
  -resultBundlePath /tmp/foil-agent-first-baseline.xcresult
```

| Change/gate | Existing verification to run when relevant |
| --- | --- |
| Shared Swift changes | Focused suites, `make test`, `make build-warnings-as-errors` |
| New rules/controller path | New focused tests plus `make test-fixture-transcription-e2e` |
| Settings/History | Focused `FoilUITests`; `make test-ui-diagnostics` for broad UI changes |
| Provider integration | `make test-provider-qa`; real configured-provider proof separately |
| Local transcription claim | `make test-local-transcription-e2e` |
| Paste/target/snapshot integration | `make test-cross-app`, `make test-queued-paste-compatibility`, real target readback |
| Dev-app permissions | `make prepare-local-permissions-dev-qa-check` |
| Quality harness structure only | `swift tests/test_live_audio_cleanup_quality.swift --dry-run` |
| Actual cleanup quality | `make test-cleanup-quality` / `make test-live-audio-cleanup-quality` with intentionally configured credentials |
| Docs | `git diff --check`, verify referenced paths/commands |

UI/paste tests run on an idle dedicated Mac or isolated QA session. Check wrappers
and app identity first: some existing commands launch or install production Foil;
do not assume every `make` target honors a Dev scheme. Add a verified Dev variant
where needed before running destructive or focus-changing scenarios on a work Mac.
No new rule acceptance test should mutate the user's real preferences or History.

The dry-run audio harness checks generated fixtures and rubric structure against
expected text; it is not a live quality evaluation. Provider UI presets do not
prove real API behavior. A localhost fixture server does not prove actual Whisper
quality. Preserve those distinctions in every receipt.

At each tranche close, retain a receipt with commit, build identity, OS/hardware,
configuration, commands, test counts/skips, raw exit status, artifact locations,
claim, strongest failure modes, evidence and residual risk. Proposed location:
`docs/evidence/agent-first-dictation/<tranche>/`. Runtime bundles may live outside
Git; link retrievable locations. Commit only synthetic/sanitized examples; private
live transcripts stay outside Git with an explicit retention/deletion plan.

Missing required evidence leaves that criterion open. Every skip needs its exact
scenario, reason, owner, and closure condition. Flaky retries preserve the first
failure and all attempts; no repeated reruns until green. Performance claims need
sample distributions, not just one fast run. Tests must fail on the injected
defects relevant to their tranche (wrong scope, double delivery, stale write,
unauthorized mutation, or timeout handling), not just on engine defects in T0.

## Rollout and release gates

1. Exercise fresh install and upgrade on Foil Dev with isolated data.
2. Complete deterministic, fault-injection, and UI/delivery evidence for the tranche.
3. Dogfood opt-in over at least 100 dictations across three work sessions; include
   agent/human app switches, long input, offline handling and recovery. Record
   correction precision, missed corrections, manual fixes, latency and failures.
   No unexplained wrong-scope replacement, data loss, or duplicate delivery passes.
   This sample supplements the adversarial tests; it does not replace them.
4. Before distribution, follow [release-process.md](../release-process.md), including
   signing/notarization/helper packaging and update-path proof; place release
   evidence in [release-qa-log.md](../release-qa-log.md). Do not publish during planning.
5. Keep opt-in defaults and the tranche's kill switch. Expand marketing claims only
   to demonstrated clients, platforms, routes and behaviors.

## Deliberately deferred

- Arbitrary regex: first prove literal rules solve real corrections. If needed,
  require a bounded-time engine or restricted grammar plus hostile-pattern tests;
  timing out an async wrapper does not stop a CPU-bound backtracking regex.
- Persistent raw/final transcript pairs, automated History mining, continuous
  clipboard watching, and automatic project inference.
- Sending/submitting prompts to selected agent conversations, task orchestration,
  screenshot attachments, multi-recording composition, and spoken instruction
  macros. These are separate product experiments with separate delivery gates.
- Server-side accounts, cloud rules sync, team distribution, iOS bridge changes,
  universal subscription reuse, and universal semantic disambiguation.

## First execution package

Start with Tranche 0 and the two PRs of Tranche 1. A first release is complete only
when a user can enable a scoped rule, see its exact effect in a real destination,
recover the original, disable it, and demonstrate that unassigned apps and existing
raw users retain their behavior. Tranche 2 begins after that evidence is recorded.
