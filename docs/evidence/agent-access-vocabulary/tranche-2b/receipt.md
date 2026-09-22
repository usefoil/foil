# Agent Access Vocabulary Tranche 2B Evidence

Date: 2026-09-21

Scope: proposal submission and status routes, validation against live Vocabulary
state and the production matcher, a pending count, and an inert review surface with
edit, omit, reject, and discard actions. Applying a proposal remains deferred to
Tranche 3.

## Submission remains inert and fails closed

Claim: a valid proposal is saved once and shown for review without changing
Vocabulary or executable local-correction rules. Disabling Agent Access preserves
the inbox while making captured or new API handlers unavailable.

Strongest realistic failure mode: a submit, reject, discard, or late in-flight
callback mutates Vocabulary, creates a second proposal after disable, or loses the
first proposal when the service stops.

Evidence:

- `AgentAccessControllerTests.testProposalSubmissionIsInertAndCapturedHandlerFailsAfterDisable`
  submits through the controller-owned router, compares Vocabulary and rule
  snapshots before and after submit and reject, disables access, proves the pending
  proposal remains available locally, and proves a captured handler returns `503`
  without creating another proposal.
- `VocabularyProposalStoreTests` covers simultaneous replay, simultaneous distinct
  submission, byte-preserving request-ID conflict and capacity errors, relaunch,
  terminal-state transitions, reviewed-content integrity, corruption, tampering,
  atomic-write failure, and owner-only `0600` persistence.
- The focused proposal/controller/HTTP suite passed **49 tests with 0 failures**:

  ```sh
  xcodebuild test -scheme Foil -configuration Debug -destination 'platform=macOS' \
    -only-testing:FoilTests/VocabularyProposalServiceTests \
    -only-testing:FoilTests/VocabularyProposalStoreTests \
    -only-testing:FoilTests/AgentAccessControllerTests \
    -only-testing:FoilTests/AgentAccessHTTPTests \
    -resultBundlePath /tmp/Foil-Tranche2B-Focused-4.xcresult
  ```

Residual risk / follow-up: Tranche 3 must add the separately reviewed transactional
apply path. Tranche 2B exposes no apply action or apply endpoint.

## Review uses current validation and preserves replay identity

Claim: submitted and user-edited proposals obey the live scope and request limits,
compile with the production correction engine, and remain idempotent under the
original agent request ID.

Strongest realistic failure mode: a proposal valid at submission becomes ambiguous
after a later Vocabulary edit, yet the review UI continues to label it valid; or a
user edit replaces the original request digest and makes an agent retry fork or
conflict incorrectly.

Evidence:

- Manual diff audit found that the first review-preview implementation did not add
  conflicts introduced by later existing-rule changes. The implementation was
  corrected to re-run full service validation against the current read model.
  `testReviewPreviewReportsConflictIntroducedAfterSubmission` now submits a valid
  proposal, introduces a conflicting live rule, and proves review becomes invalid
  with no synthetic examples.
- `testSemanticReplayReturnsOriginalAfterReviewEditAndDifferentPayloadConflicts`
  proves an exact retry still returns the original proposal after user edits while
  a different payload with the same request ID returns a conflict.
- Service tests reject empty, excessive, duplicate, ambiguous, invalid-scope,
  future-schema, overlong-note, and existing-rule-conflict requests without creating
  the store.
- `make test-local-correction-engine` passed all 18 harness tests, all 120 development
  fixtures, and the 150-case production-engine gate.

Residual risk / follow-up: matcher semantics are unchanged. Fuzzy or regex matching
requires its own corpus, false-positive budget, and performance review.

## Contract, privacy, and regression safety

Claim: the self-describing contract exposes the two proposal operations without
returning proposal content, and the new shared code does not regress adjacent Foil
behavior.

Strongest realistic failure mode: aliases, replacements, notes, transcripts,
credentials, or provider state appear in API responses or diagnostics; OpenAPI and
runtime routes drift; or focused tests pass while the full app fails to compile or
an adjacent suite regresses.

Evidence:

- The live Unix-socket privacy test seeds forbidden provider, credential, History,
  source-app, file-path, proposal-alias, replacement, and note values, then scans all
  exposed responses and captured diagnostics and finds none. It also compares
  Vocabulary and rule snapshots before and after preview and proposal submission.
- HTTP contract tests compare the exact seven operations and routes in instructions,
  runtime routing, and OpenAPI, including `201` create, `200` replay, and stable
  `400`, `404`, `409`, `422`, `429`, and `503` error mappings.
- Final `make test`: **922 passed, 0 failed, 4 skipped**. The skips are existing
  opt-in live tests. Result bundle:
  `/Users/jeremywatt/Library/Developer/Xcode/DerivedData/Foil-esfjepbizuurueaqxtjtjhkgjxxc/Logs/Test/Test-Foil-2026.09.21_18-43-45--0700.xcresult`.
- Final `make build-warnings-as-errors` passed.
- `make test-ci-scripts` passed all workflow, inventory, cleanup, fixture-reuse,
  shard-runner, and aggregate contract checks. The UI inventory reports 89 assigned,
  1 hardware-dependent exclusion, and 0 errors.
- `git diff --check`, `plutil -lint Foil.xcodeproj/project.pbxproj`, and
  `python3 -m json.tool Foil/Resources/AgentAccessOpenAPI.json` passed.

Residual risk / follow-up: the new focused UI test compiled but did not execute on
this host. The runner failed before the test body with `Timed out while enabling
automation mode`; diagnostics are preserved under
`/tmp/Foil-Tranche2B-UI-1.xcresult/Staging/1_Test/Diagnostics/`. Hosted UI CI or a
healthy local XCTest automation session must execute
`FoilUITests.testAgentVocabularyProposalRemainsReviewableAfterAccessIsDisabled` before
the UI portion is considered acceptance-gated. The test is explicitly assigned to
hosted focused UI shard D and to the complete deterministic UI inventory so a green
PR cannot silently omit it.

The first explicit hosted execution on PR #431 disproved the original UI-test path
assumption: the runner's temporary-directory prefix made the socket path exceed
macOS's Unix-socket limit, and Foil correctly failed closed before submission. The
test artifact showed the `error` state and unchanged toggle. UI tests now derive a
short per-session Agent Access root from a SHA-256 digest; a focused unit test proves
the resulting path is stable across relaunch and passes the production socket-path
validator.

## Review tooling

Claim: the branch received a second review pass after implementation.

Strongest realistic failure mode: the implementation passes its authored tests but
contains an untested integration error.

Evidence: `codex review --uncommitted` was attempted. The installed CLI refused the
configured `gpt-5.6-sol` model because it requires a newer Codex version, so no CLI
review result is claimed. A direct manual audit then found and fixed the stale
review-validation defect described above, followed by the focused and full-suite
reruns.

Residual risk / follow-up: hosted code review remains required before merge.
