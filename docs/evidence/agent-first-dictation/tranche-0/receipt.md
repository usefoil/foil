# Tranche 0 evidence — 2026-09-14 (updated 2026-09-19)

Status: test foundation implemented; full tranche acceptance remains open for the
specific external/integration evidence listed below. No local correction engine
or new Vocabulary behavior has shipped.

Base commit: `320cc02c7f3f6a9e3d67fa975c4ecda5649d0949`, plus this working-tree patch.
Host: Mac14,15 / arm64, macOS 26.5.1; Xcode 26.3 (17C529).

## What changed

- Frozen [v1 matching contract](../../../../tests/fixtures/local-corrections/contract.md).
- 120 explicit development cases (40 positive, 60 negative, 20 edge) and 30
  separately authored/reserved holdout cases, with frozen SHA-256 hashes.
- Python adapter/comparison gate, four deliberate bad implementations, benchmark
  workload generator, raw-sample validator, and 18 tests of the harness itself.
- Two actual controller tests: raw vocabulary/Unicode preservation with a rejecting
  transport spy, and an attached raw-controller timing baseline.
- Isolated baseline runner: private test host ID/storage plus disabled updater
  startup in a temporary copy. Production processing source is unchanged.
- `make test-local-corrections-contract` and a dedicated required CI job, including
  fixture-only changes. No workflow dispatched and no release performed.

## Claim: the gate rejects plausible bad corrections

Strongest realistic failure: a green harness merely compares its own generated
answers, misses changed Unicode bytes, or treats missing adapter output as success.

Evidence:

- `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests -p test_local_corrections_harness.py -v`
  completed with **18 tests, zero failures**.
- `python3 tests/local_corrections_harness.py --report /tmp/foil-tranche0-contract-receipt-20260914.json`
  validates the frozen corpus and rejects four deliberate defects. See
  [contract-receipt.json](contract-receipt.json):
  - `N01`: substring mutant changes `super bases`.
  - `N21`: wrong-scope mutant changes text in the human group.
  - `N31`: disabled-rule mutant still changes text.
  - `E01`: cascading mutant produces `C C` instead of expected `B C`.
- An actual external no-op Python adapter fails every positive fixture. Missing,
  extra, duplicate and reordered replies, malformed output, nonzero exit, and
  timeout are rejected. Expected output/reasons never enter adapter requests.
- Comparator tests reject NFC rewriting of untouched decomposed text by comparing
  UTF-8. Corpus-validator tests reject hash drift and invalid definitions even
  after a deliberate rehash.

Residual risk: these are intentionally broken witnesses, not a full reference
matcher. `production_engine: NOT_RUN` is deliberate. The actual Swift engine must
pass all cases in T1; fixture counts and a green validator cannot substitute.

## Claim: latency checks cannot pass on a fast but incorrect no-op

Strongest realistic failure: benchmark measures IPC, uses Debug numbers as Release
proof, returns unchanged text, reports only a mean, or hides slow-tail samples.

Evidence:

- Fixed-seed (20260914) workloads contain 500 rules/10 KiB and 1,000 rules/64 KiB.
  Generation command:
  `python3 tests/local_corrections_harness.py --write-benchmark-workloads /tmp/foil-tranche0-benchmark-workloads-20260914.json`.
- Validator tests reject wrong output digest, wrong boundary/configuration/size,
  missing cold or warm samples, negative/nonfinite timings, and a p99 failure
  despite a fast median. Each scenario requires 50 cold compile, 50 cold controller,
  and 1,000 warm controller samples. No fake report is retained as performance proof.
- Existing raw-controller test executed 50 fresh-controller calls and 1,000 warm
  calls per input size, checked exact bytes outside the timing interval and zero
  transport requests, and attached actual samples to xcresult. Retained sanitized
  arrays: [raw-controller-baseline.json](raw-controller-baseline.json).

| Existing raw path, Debug | Warm p95 | Warm p99 |
| --- | --- | --- |
| 10 KiB | 0.140333 ms | 0.151875 ms |
| 64 KiB | 0.143875 ms | 0.151250 ms |

These are **raw bypass timings**, not correction-engine results or end-to-end
dictation latency. Controller construction is outside the timing interval; “cold”
means first call on a fresh controller. The baseline has no rule compilation.

Residual risk: the real Release adapter and its instrumentation must be inspected
and measured in T1, including Intel hardware. A report naming a boundary is still
a claim until matched to actual instrumentation.

## Existing-app baseline attempts (all retained)

1. `/tmp/foil-tranche0-baseline-20260914/` — Release attempt, exit 65 before tests.
   Existing suites reference DEBUG-only `KeychainHelper` overrides and mock state.
   `ENABLE_TESTABILITY=YES` does not expose conditional-compilation test hooks.
   This was a runner configuration error, not proof the production Release app
   fails to compile. Baseline runner now defaults to Debug.
2. `/tmp/foil-tranche0-baseline-debug-20260914/` — **302 executed, 301 passed, one
   failed**, exit 65. Controller (53), History (56), CleanupGroup, PasteQueue, and
   QueuedPaste suites passed. The sole failure was
   `AppStateTests.testAccessibilityRecoveryDetailExplainsStaleIdentityRepairPath`:
   the initial isolation copy identified as Foil Dev, while the existing assertion
   expects “remove the old Foil entry.” The controller timing attachment above is
   from this run. The failure was not removed or relabeled a pass.
3. `/tmp/foil-tranche0-baseline-isolated-20260914/` — corrected isolation preserves
   normal naming, changes only bundle/storage namespace and updater startup. Direct
   file comparison verifies all other product Swift files and controller tests
   equal the working tree. The first run stalled in XCTest session setup before
   executing any test; sampled stack shows `XCTestDriver._prepareTestConfigurationAndIDESession`
   waiting for `XCTFuture`. Only this run's xcodebuild/host were stopped (exit -15).
   Sample: `/tmp/foil-tranche0-host-sample.txt`; isolation patch and metadata are
   retained with the result bundle. One bounded retry uses identical source/build
   and a separate `retry.xcresult`; it hit the **300-second timeout (exit 124)**
   without any test results. `retry.log`, `retry-metadata.json`, and the result
   bundle are retained. The remaining isolated test host was stopped by its exact
   executable path. No shared testmanager daemon or normal Foil process was killed.

The new isolation test checks the copied project IDs, private storage path,
disabled updater and byte-identical processing/test sources. It does not mutate
normal Foil settings. No broad `make test` was run on the ordinary product identity.

## Claim: fixture-only changes cannot bypass the new CI gate

Strongest realistic failure: the existing app-change classifier ignores `tests/`,
so all tests are skipped and CI still appears green.

Evidence: the new `local-correction-contract` job is unconditional and `ci-gate`
depends on it. CI Gate explicitly requires its result to be `success`, independent
of the app-change flag. Parsed the actual YAML with Ruby YAML; executed the actual
gate shell with ten combinations (code-change true/false × success/failure/
cancelled/skipped/empty). Only success passes, including when Mac jobs are skipped.
The `make` target also completed successfully. `git diff --check` passes.

Residual risk: GitHub-hosted execution has not run; local gate validation is not a
claim that a remote workflow passed.

## Open criteria and exact closure conditions

| Open evidence | Reason / owner / closure |
| --- | --- |
| Clean final isolated baseline | Closed 2026-09-19: fresh-worktree run passed 302/302 with zero skips; raw exit and xcresult independently agree. Prior attempts remain recorded above. |
| Dedicated real cross-app baseline | `make test-cross-app` and `make test-queued-paste-compatibility` were not run: they drive the active desktop, and existing wrappers can use production Foil. Tranche 0 QA owner: run on an idle dedicated Mac with verified dev identity and read back actual target text. Simulated queue tests are not physical insertion evidence. |
| Independent holdout review | Same author wrote/reviewed this corpus. Tranche 0 reviewer: review the 30 reserved cases against the frozen contract before an independent-review claim. The set has not been used to tune a production matcher. |
| Actual local-engine timing and correctness | No local engine exists yet. Tranche 1 owner: connect the real Swift adapter, run corpus/holdout and Release benchmark with measured cold/warm samples. |
| Intel performance | Only an Apple Silicon host was measured. Tranche 1 QA owner: execute the same Release workloads on Intel before making cross-platform speed claims. |

No requested app functionality was changed, no rule was activated, and no release
was made. The first implementation package remains the T1 engine/store and its
adapter, followed by integration into the existing Vocabulary UI.

## Fresh-worktree continuation — 2026-09-19

Created a managed worktree at
`/Users/jeremywatt/.codex/worktrees/foil-local-corrections-tranche-zero/foil`
on branch `codex/local-corrections-tranche-zero`, from the original base commit.
Copied and byte-verified all 14 tranche-0 files. Seven unrelated dirty source files
were excluded; the original checkout was preserved.

Claim: the corrected isolated baseline completes cleanly on a fresh run.
Strongest realistic failure: console success hides skipped/failed tests, or the
worktree accidentally incorporates unrelated app changes.
Evidence: the copy comparison verified the exact tranche files and confirmed the
seven excluded files equal HEAD. Eighteen harness tests and all four mutant
checks passed again in the new worktree. Ran:

```sh
python3 scripts/run-local-corrections-baseline.py --output /tmp/foil-tranche0-fresh-worktree-20260919
xcrun xcresulttool get test-results summary --path /tmp/foil-tranche0-fresh-worktree-20260919/baseline.xcresult --compact
```

The runner exited 0 and xcresult reports **302 passed, 0 failed, 0 skipped**.
See [the retained run receipt](fresh-worktree-baseline-20260919.json) for identity,
exact command, and artifact paths. This closes the clean-baseline gate without
concealing the earlier failures. It does not establish a root cause for the earlier
XCTest startup stall or claim the startup issue can never recur.

Residual risk: dedicated real cross-app readback and independent holdout review
remain open. No production local correction engine or Release performance was
claimed. All continued edits for this task belong in the new worktree.
