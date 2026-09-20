# Tranche 1 evidence receipt

Date: 2026-09-20
Worktree: `/Users/jeremywatt/.codex/worktrees/foil-local-corrections-tranche-zero/foil`
Branch: `codex/local-corrections-tranche-zero`

## Implemented vertical slice

- Versioned local phrase rules with global or Cleanup Group scope, explicit enable,
  case sensitivity, preview, and Vocabulary create/edit/disable/delete controls.
- NFC matching with ASCII-only case folding, original byte preservation outside
  replacements, deterministic overlap precedence, protected code/URL spans, and
  frozen 1,000-rule/64 KiB limits.
- Validated atomic persistence with revision conflicts and fail-closed handling for
  corrupt or future schemas.
- A captured rule/scope/revision snapshot runs after transcription and before
  optional Cleanup. Cleanup failure returns the locally corrected transcript.
- Latest provider text is retained in memory for Copy/Paste original recovery and
  is cleared with History or process exit. It is never serialized to History.
- Localhost fixture E2E support records every server request and asserts one
  transcription request, exact corrected output, and visible recovery controls.

## Claims, failure modes, and proof

### Exact matching and determinism

Claim: the production Swift engine implements the frozen oracle.

Strongest realistic failure mode: the adapter is a no-op, tunes against only the
development split, changes untouched Unicode bytes, leaks across scope, or rescans
replacement output.

Evidence:

- `make test-local-correction-engine` passed all **150/150** development and held-out
  fixtures through the compiled Swift adapter.
- The gate's deliberately broken substring, scope, disabled-rule, and recursive
  adapters were rejected by independent expected strings.
- `LocalCorrectionEngineTests` passed 10,000 fixed-seed generated cases in both
  original and reversed rule order, with wrong-scope distractors, protected code
  and URLs, exact UTF-8 comparisons, and bounded output assertions.

Residual risk: the same author still owns the 30-case holdout. Independent review
of those expected strings remains open.

### Persistence and upgrade safety

Claim: local rules are opt-in and cannot corrupt existing Vocabulary/provider state.

Strongest realistic failure mode: interrupted writes partially replace the file;
corrupt/future data silently enables corrections; repeated promotion duplicates a
rule; a failed delete removes Vocabulary while leaving its executable rule.

Evidence: focused store/AppState tests exercised missing data, reload, repeated
promotion, revision conflict, corrupt and future schemas, an injected interrupted
write, edit propagation, and deletion write failure. The failure test compared file
bytes and retained both the Vocabulary pair and rule. Existing processing settings
were reloaded unchanged. No automatic migration runs; promotion is an explicit UI
choice, so there is no upgrade-time rule activation.

### Pipeline, fallback, and recovery

Claim: a local-only path sends no Cleanup request, captures delayed-operation state,
and does not lose the successful provider transcript when Cleanup fails.

Strongest realistic failure mode: a delayed call reads the newly selected group or
rule revision, Cleanup failure returns the pre-correction text, History persists the
raw text, or History-off recovery writes transcript content.

Evidence:

- Rejecting transport spies proved zero Cleanup calls in Raw mode.
- A delayed transcription test deleted its group and changed rules while the
  provider call was suspended; the pending call used the captured group/revision,
  and the next call used current state.
- The Cleanup 500 test observed corrected text in the Cleanup request and callback,
  while `originalText` retained the provider text.
- History tests inspected `history.json` bytes, reconstructed the store, exercised
  History off, and cleared state. Raw text remained memory-only and disappeared on
  reconstruction/clear.
- The fixture E2E gate is available as `make test-local-correction-fixture-e2e`.
  It asserts an exact result and a one-line `/v1/audio/transcriptions` request log;
  any Cleanup/agent request makes the gate fail.

Residual risk: isolated arm64 test hosts built successfully and launched their
XCUITest runners three times, including at PR head `4231698`, but macOS rejected
UI-test initialization each time with
`com.apple.LocalAuthentication` code `-4` (`System authentication is running`).
The test body and fixture assertions never ran. This remains an open gate, recorded
as a blocked attempt in `fixture-e2e-attempt-20260920.json`, and still needs an idle
UI-test host for the screenshot and server-request receipt.

### Downgrade retention

Claim: returning to the previous released app retains additive local-correction
data so the current app can read it again.

Strongest realistic failure mode: the previous app deletes or rewrites the unknown
file, or the current store cannot decode the retained bytes.

Evidence: an isolated build from the exact `v1.14.1` commit
`0e724488c2b415fa18194e21cc0a49f828a096ee` launched with bundle identifier
`com.neonwatty.Foil.PR421Downgrade` against a dedicated Application Support
directory. The rule file SHA-256 was
`692d57f5450a43738ee1fbfb60a091b3e4a6eaf10ddae112589a3cbc842f26ba`
before and after the previous app ran. The current production
`LocalCorrectionStore` then decoded schema 1, revision 1, the enabled state, and
the scoped `super base -> Supabase` rule. The isolated app passed strict deep code
signature verification; the installed production Foil process remained running.
The structured receipt is `downgrade-retention-v1.14.1.json`.

### Performance

Claim: the controller-level local path meets the frozen budget on Apple Silicon
and Intel in an optimized Release configuration.

Strongest realistic failure mode: a fast no-op is measured, compilation is hidden,
only averages are reported, or the benchmark bypasses the controller.

Evidence: `make test-local-correction-performance` generated the fixed-seed workloads,
ran 50 compilations, 50 fresh-controller calls, and 1,000 warmed calls per scenario
at `TranscriptionController.processTranscriptOrRaw`, verified the output SHA-256,
retained every timing sample, and passed the tranche-zero validator. GitHub Actions
run [35519491914](https://github.com/usefoil/foil/actions/runs/35519491914) repeated
the benchmark on an `x86_64` runner at PR head `9df2247` and passed the same fixed
limits.

| Apple Silicon workload | Compile p95 | Cold controller p95 | Warm p50 | Warm p95 | Warm p99 |
| --- | ---: | ---: | ---: | ---: | ---: |
| 500 rules / 10 KiB | 15.04 ms | 0.52 ms | 0.43 ms | 0.44 ms | 0.47 ms |
| 1,000 rules / 64 KiB | 58.62 ms | 1.43 ms | 1.39 ms | 1.41 ms | 1.43 ms |

| Intel workload | Compile p95 | Cold controller p95 | Warm p50 | Warm p95 | Warm p99 |
| --- | ---: | ---: | ---: | ---: | ---: |
| 500 rules / 10 KiB | 73.44 ms | 1.97 ms | 1.55 ms | 2.16 ms | 2.37 ms |
| 1,000 rules / 64 KiB | 256.56 ms | 4.28 ms | 3.24 ms | 4.36 ms | 5.23 ms |

Raw samples and output hashes are in
`local-correction-release-performance-apple-silicon.json` and
`local-correction-release-performance-intel.json`. Both artifacts contain 50 cold
compilations, 50 fresh-controller calls, and 1,000 warmed calls for each workload.
The output hashes match across architectures. The Intel artifact SHA-256 is
`6cfa377847019164908531109c6a8f9217393855b53e643410c36e460bae598a`;
the exact-head Apple Silicon artifact SHA-256 is
`10fc5c85ffa0580c55e5cd3f9a4f234bf2c878a5bef81798f3398b95167b663d`.

Residual risk: a dedicated interaction trace for maximum-size processing is still
open; these controller timings do not by themselves prove main-thread responsiveness.

## Verification summary

- Focused Xcode selection: **81 passed, 0 failed, 0 skipped** across engine, store,
  History, AppState, and controller paths.
- `xcodebuild build-for-testing` passed, compiling the new XCUITest and E2E hooks.
- Foil and FoilDev builds passed with Swift warnings treated as errors.
- Shell syntax, Node syntax, and `git diff --check` passed.
- All required PR checks passed at optimized commit `9df2247`: build, unit tests,
  four focused UI shards, audio snapshots, local-correction contract, and the
  aggregate CI gate. The temporary Intel evidence job also passed.

An exploratory `build-for-testing` with warnings promoted across every existing
test source failed on pre-existing warnings in `PasteQueueTests` and other legacy
tests. The ordinary `build-for-testing` gate passed, and both app products remained
warning-clean. No warning-clean test-target claim is made.

One broader controller attempt was interrupted after the macOS test host stalled
inside an existing Keychain `SecItemAdd`. The new test removed its unnecessary
Keychain write and passed in the 81-test focused run. This receipt does not relabel
the interrupted broad attempt as green.

## Remaining tranche gate

- Run `make test-local-correction-fixture-e2e` on an idle desktop and retain its
  XCUITest screenshot, exact result, and request log.
- Perform the exit demo with actual insertion into TextEdit and one installed coding
  agent composer, read back both targets, recover the original, and disable the rule.
- Review the 30 held-out expectations independently.
- Capture an interaction trace during maximum-size local processing and verify the
  main UI remains responsive.
