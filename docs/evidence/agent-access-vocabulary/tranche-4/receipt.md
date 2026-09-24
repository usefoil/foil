# Agent Access Vocabulary Tranche 4 Evidence

Date: 2026-09-24

Scope: add a deterministic Agent Access gate, exercise two signed packaged app
bundles outside XCTest over real Unix sockets, and publish the copied-command user
workflow. This tranche does not publish a release or add an agent apply route.

## Copied-command flow works in signed Foil and Foil Dev bundles

Claim: a local agent can begin with the copied curl command, discover the contract,
list scopes, preview exact corrections, submit an inert proposal, and read its
status from signed Foil and Foil Dev processes without any plugin, skill, MCP
registration, or helper installation.

Strongest realistic failure mode: the in-process tests pass while a packaged app
has a broken signature/resource layout, curl cannot reach its Unix socket, or Foil
and Foil Dev collide on one socket or proposal file.

Evidence:

- `scripts/run-agent-access-installed-smoke.sh` copied freshly built Foil and Foil
  Dev app bundles into a temporary Applications directory and ran
  `codesign --verify --deep --strict` on both. Their bundle identifiers were
  independently checked as `com.neonwatty.Foil` and `com.neonwatty.Foil.Dev`.
- Both apps ran concurrently with isolated temporary state. Real `/usr/bin/curl`
  calls retrieved instructions and scopes, previewed `super base` / `Superbase` ->
  `Supabase` plus `codecs` -> `Codex`, submitted proposals, and read matching
  pending status receipts.
- The smoke proved distinct sockets, distinct owner-only `0600` proposal stores,
  distinct proposal IDs/content, and distinct v2 catalogs. It finished with
  `status=pass`, `signatures=verified`, `socket_isolation=verified`, and
  `proposal_store_isolation=verified`.
- `make test-agent-access` passed 104/104 focused contract, parser, server,
  lifecycle, concurrency, privacy, persistence, reviewed-apply, crash-recovery,
  and transcription tests. Result bundle:
  `/tmp/Foil-Tranche4-AgentAccess.xcresult`.

Residual risk / follow-up: no separate visible Codex task was created because the
user did not request task creation, so the smoke executes the same
self-describing command sequence directly rather than claiming a fresh-task
operator pass. The harness uses DEBUG-only isolated-state and shutdown controls;
a future release candidate must use the separate Notarized QA Build and installed
production QA workflows rather than claiming notarization from this script.

## Live shutdown is fail closed and does not mutate Vocabulary

Claim: turning Agent Access off closes the live service while preserving the exact
catalog and received proposals for local review.

Strongest realistic failure mode: the UI reports Off while a listener remains
reachable, a partial connection writes after shutdown, or shutdown rewrites
Vocabulary/proposal state.

Evidence:

- The installed smoke enabled both services, exchanged requests, then used a
  DEBUG-only test control that can only disable Agent Access. Both socket files
  disappeared, a subsequent curl could not connect, and the persistent ownership
  lock files were owner-only and immediately reacquirable (unlocked).
- SHA-256 hashes for each app's v2 catalog and proposal store were identical before
  and after disable. This rules out a shutdown-side Vocabulary or inbox write.
- `AgentAccessControllerTests.testRealServerDisableClosesPartialClientAndRemovesSocket`
  and `testDisableWaitsForInFlightProposalCommitBeforeReportingOff` cover partial
  connections and accepted in-flight proposal work. Both are in the 104/104 gate.

Residual risk / follow-up: the lock file intentionally remains in place so every
future process synchronizes on the same inode; deleting it on shutdown would create
a cross-process locking race. The runtime socket is the removable/reachable
artifact.

## Reviewed apply remains local, scoped, recoverable, and private

Claim: agents cannot apply changes; after user review, exact corrections preserve
scope and original recovery text, and payload content does not leak to diagnostics
or status receipts.

Strongest realistic failure mode: an undocumented remote apply path exists,
`codecs` changes outside its reviewed scope, History loses the provider text, or
proposal content appears in diagnostics/status.

Evidence:

- The instructions/OpenAPI/runtime parity tests enumerate exactly seven read,
  preview, propose, and status operations with no apply route. The ordinary proposal
  state transition still cannot manufacture an applied state without a durable
  catalog receipt.
- `testReviewedScopedProposalAppliesThroughCatalogAndReconcilesInbox` and
  `testCoordinatorAppliesReviewedAliasesAtomicallyWithoutEnablingGlobalSwitch`
  prove one reviewed three-alias commit, disabled/global-switch preservation, and
  byte-identical output outside the selected scope.
- `testReviewedAgentAliasesCorrectExactDictationAndHistoryKeepsOriginal` proves
  `Superbase and codecs` becomes `Supabase and Codex` in the agent scope while the
  recovery text remains `Superbase and codecs`.
- The installed smoke seeded a unique proposal-note canary and found it in neither
  status responses nor either diagnostic log. The focused privacy test additionally
  scans seeded vocabulary, transcript, source-app, path, provider, and credential
  values across all exposed responses and captured diagnostics.

Residual risk / follow-up: no live microphone was used in this tranche. The
production transcription controller and History path ran deterministically; a
hardware dictation into Codex remains a manual release-candidate check.

## Regression and release closeout

Claim: the new proof harness and test-only shutdown control do not weaken release
compilation or matcher performance.

Strongest realistic failure mode: focused tests pass while the full suite, warning
build, matcher corpus, performance tail, shell scripts, or active desktop UI fails.

Evidence:

- `make build-warnings-as-errors`: `BUILD SUCCEEDED`.
- `make test`: 947 passed, 0 failed, 4 existing opt-in skips (951 total). Result:
  `/Users/jeremywatt/Library/Developer/Xcode/DerivedData/Foil-adjtcmdjusydqqgwuwxafogqpfcu/Logs/Test/Test-Foil-2026.09.24_07-45-00--0700.xcresult`.
- `make test-local-correction-engine`: 18 harness tests, 120 development fixtures,
  and all 150 production-engine fixtures passed.
- `make test-local-correction-performance`: normal p95 0.455 ms / p99 0.468 ms;
  maximum p95 1.402 ms / p99 1.417 ms, with all cold budgets passing.
- `shellcheck` and `bash -n` pass for both new scripts. `git diff --check`, OpenAPI
  JSON parsing, and project-file `plutil -lint` pass.
- The focused UI command compiled the app and UI test bundle but failed before
  either test body when macOS timed out enabling XCTest automation. Result bundle:
  `/tmp/Foil-Tranche4-AgentAccess-UI-2.xcresult`. This is recorded as a skip. The
  same reviewed-apply and toggle/copy rows passed hosted UI shard D in final green
  Tranche 3B CI run `36012845328`.

Residual risk / follow-up: active-desktop UI proof remains dependent on a healthy
macOS automation session. Notarization/stapling and live microphone proof are
release-candidate gates, not passes here, because this task explicitly does not
publish a release.

## Review tooling

Claim: the closeout included an adversarial pass rather than relying only on the
authored happy path.

Strongest realistic failure mode: the smoke encodes an unsafe lifecycle assumption
or its cleanup can target an arbitrary caller-provided path.

Evidence: the first installed smoke failed because it expected shutdown to delete
the ownership lock. Direct server inspection showed that retaining one stable lock
inode is required for safe cross-process synchronization, so the smoke now proves
the file is `0600` and unlocked instead. Manual audit also replaced deletion of a
caller-provided result-bundle path with a fail-closed “already exists” error.
The repository `codex-review` helper was attempted with full access, but the
installed CLI cannot use its configured `gpt-5.6-sol` review model until the CLI is
upgraded. No automated clean-review claim is made.

Residual risk / follow-up: upgrade the local Codex CLI before relying on the helper
for a later release review.
