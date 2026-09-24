# Agent Access Vocabulary Tranche 3B Evidence

Date: 2026-09-24

Scope: activate the version-2 Vocabulary catalog, route current mutations through
one coordinator, and let the user apply a reviewed Agent Access proposal. This
tranche adds no remote apply route and does not publish a release.

## Reviewed apply is atomic, scoped, and user controlled

Claim: applying the reviewed `Superbase` / `super base` -> `Supabase` and `codecs`
-> `Codex` proposal creates three visible corrections and three linked `agents`
rules in one catalog revision without enabling local corrections.

Strongest realistic failure mode: metadata commits without executable rules, an
ordinary `codecs` occurrence changes outside the reviewed scope, or apply silently
turns on the global switch.

Evidence:

- `VocabularyCatalogStoreTests.testCoordinatorAppliesReviewedAliasesAtomicallyWithoutEnablingGlobalSwitch`
  asserts one revision, three itemized receipt rows, three metadata/rule pairs,
  inactive behavior while the switch is off, corrected `Supabase and Codex` in the
  `agents` scope after enable, and byte-identical text in another scope.
- `AgentAccessControllerTests.testReviewedScopedProposalAppliesThroughCatalogAndReconcilesInbox`
  exercises review revision, apply, inbox reconciliation, the persisted off switch,
  then production-engine correction and scope isolation.
- `TranscriptionControllerTests.testReviewedAgentAliasesCorrectExactDictationAndHistoryKeepsOriginal`
  proves the exact dictation becomes `Supabase and Codex` with no cleanup request,
  while History keeps `Superbase and codecs` as the recoverable original.
- The focused direct XCTest run executed 329 tests. The changed suites passed:
  catalog 17/17, proposal service/contract/store 32/32, controller 14/14, local
  store 8/8, and transcription 64/64 with one existing opt-in skip. Log:
  `/tmp/Foil-Tranche3B-direct-focused.log`.

Residual risk / follow-up: the new XCUITest compiled, but this desktop's XCTest
manager timed out before enabling automation and then could not materialize later
test workers. The focused row is assigned to hosted UI shard D before merge. Its
first hosted run exposed an older proposal-review assertion that assumed one
replacement field; the seed now contains two corrections, so the assertion was
made explicitly first-match and the exact apply row was added to the hosted shard.
The next hosted result bundle exposed the exact interaction failure: the action
buttons were four points below the sheet viewport, so they were not hittable and
the generic coordinate fallback landed outside the sheet. The tests now scroll the
proposal sheet until the chosen action is genuinely hittable, then prove rejection
through the zero-pending inbox count and apply through the three durable catalog
rows.

## Failure, stale-review, replay, and crash boundaries fail closed

Claim: review validation and the single catalog commit cannot leave durable
metadata/rule divergence or duplicate an applied request.

Strongest realistic failure mode: a failed rename leaves a partial applied catalog,
a concurrent UI edit is overwritten, or a crash between catalog commit and proposal
state update makes a retry duplicate corrections.

Evidence:

- `testCoordinatorApplyCommitFailureLeavesCatalogByteIdenticalAndNoReceipt` injects
  failure at the commit boundary and proves the prior catalog bytes, empty metadata,
  empty rules, and empty receipt ledger remain unchanged.
- `testConcurrentVocabularyEditRejectsStaleReviewedApply` applies after a catalog
  edit and proves only the UI edit remains, the proposal stays pending, and review is
  marked stale.
- Coordinator replay returns the durable receipt without advancing revision.
  `testReceiptReconciliationRecoversCrashAfterCatalogCommit` independently rebuilds
  proposal state from that receipt after the simulated interruption.
- The ordinary proposal transition API still rejects `.applied`; only a matching
  durable catalog receipt can mark the inbox row applied.

Residual risk / follow-up: cancellation and abrupt HTTP disconnect cannot invoke
apply because apply is local UI-only. Installed process interruption is covered by
receipt reconciliation on refresh/relaunch and remains part of Tranche 4 smoke.

## Migration and compatibility remain fail closed

Claim: production startup adopts the v2 catalog without modifying either legacy
source, while ordinary unit tests retain their isolated v1 fixtures.

Strongest realistic failure mode: a current UI mutation writes legacy bytes, an old
release edits legacy state and current Foil overwrites one side, or test-only launch
detection accidentally disables the catalog in the XCUITest app.

Evidence:

- `testAppStateCatalogMutationLeavesLegacySourcesUntouched` performs metadata and
  linked-rule mutations through production `AppState`, reloads v2, and asserts the
  UserDefaults and schema-v1 file bytes are unchanged.
- Tranche 3A corrupt/future schema, interrupted migration, fingerprint mismatch,
  owner-only permission, stale revision, and linked-rule divergence tests remain in
  the 17/17 passing catalog suite.
- Catalog activation explicitly treats `--ui-testing` as production-like while
  retaining isolated legacy paths for hosted unit-test processes and direct
  `xctest` execution.

Residual risk / follow-up: the direct AppState run passed 193/194 tests. The sole
failure is a pre-existing harness assertion that unwraps Xcode's injected test
configuration URL, which is absent by construction under direct `xctest`; it is not
a product or changed-path failure.

## Regression and review closeout

Claim: the coordinator wiring does not change matcher behavior or introduce build
warnings.

Strongest realistic failure mode: focused apply tests pass while matcher boundaries,
Release compilation, or adjacent shared code regress.

Evidence:

- `make test-local-correction-engine` passed all 18 harness tests, all 120
  development fixtures, and the 150-case production-engine gate.
- `make build-warnings-as-errors` completed with `BUILD SUCCEEDED`.
- `xcodebuild build-for-testing` completed with `TEST BUILD SUCCEEDED` after the
  final source change.
- `plutil -lint Foil.xcodeproj/project.pbxproj` and `git diff --check` pass.
- The `codex-review` helper was attempted with `--uncommitted --full-access`; the
  installed CLI refused its configured model because it requires a newer Codex
  version. No automated clean-review claim is made. Manual diff audit found and
  fixed the inherited-XCTest/UI-test catalog activation boundary.

Residual risk / follow-up: `make test-local-correction-performance`, `make test`,
and the focused XCUITest reached Xcode's pre-test worker-materialization boundary
and did not execute on this desktop. They remain required hosted merge gates; the
failure is recorded as a skip, not a pass.
