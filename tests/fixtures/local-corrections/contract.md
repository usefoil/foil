# Local correction contract v1

Frozen before implementation on 2026-09-14. This is an acceptance contract, not
an implemented feature. The corpus and Python harness contain **no production
matcher**. Its mutation checks prove the oracle can reject selected defects, not
that any engine currently passes the corpus.

## Matching decisions

- Literal phrase replacement only. No regex, fuzzy matching, spelling inference,
  whitespace collapsing, or implicit service-name rules.
- `enabled: false` for the operation means verbatim. Disabled rules are ignored.
- A rule with `group: null` is explicitly global. Otherwise its group ID must equal
  `active_group` exactly. Null/unknown context never selects another group's rules.
- NFC canonical equivalence is supported: composed `café` and decomposed
  `cafe\u0301` match. Do not use compatibility normalization (NFKC/NFKD).
- `case_sensitive: false` folds **ASCII A–Z only in v1**. It does not expand `ß`
  into `ss`, fold Turkish dotted I, or infer case equivalence for other scripts.
  Name this behavior clearly in the implementation/API; Unicode case folding is a
  future contract change. Non-ASCII literal names still match canonically.
- Surrounding Unicode letters, numbers, combining marks, or underscore prevent a
  match. Combining marks are included conservatively so a replacement cannot split
  a grapheme. Do not take a partial match within a normalized original grapheme.
  Boundaries are checked outside the entire phrase, including punctuation sources.
- Whitespace *inside* a source is literal: space, tab, NBSP, CRLF and repeated
  spaces are distinct. Do not trim transcript input or output.
- Resolve candidates left to right in original input. At the same original start,
  group scope beats global, then longest normalized source in Unicode scalars,
  then lexicographically smallest stable rule ID. Rule-array order is irrelevant.
- Emit replacement text exactly, including its case, dollar signs, backslashes,
  emoji or explicit newline. Replacement output is never scanned again. Separate
  original occurrences still match; `A B` under `A->B, B->C` becomes `B C`.
- Rule storage rejects identical normalized source/scope/case-mode entries with
  conflicting replacements, including disabled entries. It also rejects ambiguous
  overlapping sensitive/insensitive definitions for the same canonical alias.
  Corpus cases describe valid engine input; storage-validation tests follow in T1.
- Bytes outside replaced spans remain unchanged, even if matching used a normalized
  view. Swift's canonical `String ==` comparison is not sufficient proof; compare
  UTF-8. Build an original-range map rather than returning the normalized input.

## Protected text

Recognition is deliberately bounded; this is not a complete Markdown parser.

- Fences begin at line start after zero to three ASCII spaces, with a run of at
  least three backticks or tildes. Opening annotation may follow. They close only
  with the same character, a run at least as long, and whitespace-only remainder
  on that line, again allowing zero to three leading spaces.
- An unclosed fence protects to EOF. Fences take precedence over inline spans.
- Outside fences, an inline backtick run closes with an equal-length run on the
  same line. An unmatched opening protects to the end of its line. A shorter run
  inside a larger span cannot close it. Ordinary quoted prose is not protected.
- Outside code, case-insensitive ASCII `http://`, `https://`, and `www.` start
  protected URL tokens extending to whitespace, `<`, `>`, or a single/double quote.
  Require token start (start of input or preceding non-letter/number/underscore)
  before the prefix. Keep trailing token punctuation protected conservatively.
  Other schemes, filesystem paths, and email addresses are not inferred as URLs
  in v1; plain identifier boundaries still apply. State these limits in help text.
- Any candidate overlapping a protected span is rejected entirely.

## Limits and failures

Initial engine limits: 1,000 enabled rules; 64 KiB UTF-8 input; 256 Unicode scalars
per source/replacement. Empty or whitespace-only source/replacement definitions
are rejected. Transcript input can be empty. Above-limit transcript input falls
back intact with a visible reason; no partial truncation or partial correction.
Validation, persistence, fallback, revision snapshots, and delivery belong to T1's
app integration tests, not merely to this valid-input string corpus.

## Corpus and review status

- `development.jsonl`: 40 positive, 60 negative, 20 edge cases.
- `holdout.jsonl`: 10 positive, 10 negative, 10 edge cases, authored separately and
  reserved for the first production candidate. These are not generated from a
  matcher. The same author reviewed them; independent review remains an explicit
  gate before claiming the plan's full holdout review requirement.
- `manifest.json`: SHA-256 hashes, exact counts and category counts. Changing
  expectations requires a rationale and deliberate manifest update in review.
  Hashes prevent accidental drift, not intentional tampering by a code author.
- Every JSONL row records input, explicit rules, active group, enable state, exact
  expected output, and why. IDs are stable regression references.
- An unconditional literal alias cannot disambiguate meaning within its scope.
  `codecs -> Codex` is unsuitable for a group where audio codecs are discussed.
  The negative fixtures use an absent/inactive rule; they do not promise semantic
  understanding from a string matcher.

## Running the gate

From the repository root, Python 3 standard library only:

```sh
make test-local-corrections-contract
```

The same checks run in CI's Local Correction Contract job on every PR/merge-group
run, including fixture-only changes that skip the Mac build jobs. CI Gate requires
that job to succeed. To run without Make's Xcode discovery:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests -p test_local_corrections_harness.py -v
python3 tests/local_corrections_harness.py
python3 tests/local_corrections_harness.py --report /tmp/foil-correction-gate.json
```

Default runs validate the corpus and kill four targeted mutants: substring matching
(`N01`), wrong scope (`N21`), disabled rule (`N31`), recursive replacement (`E01`).
The mutation implementations are deliberately incomplete bad candidates, not a
reference engine. The runner labels production-engine execution `NOT_RUN`.

T1 must supply an executable adapter over the **actual Swift engine**, using JSONL
stdin/stdout. Pass its executable and arguments after `--adapter` (last option).
Use `--split development` while implementing and `--split holdout` for the frozen
challenge gate; all cases are required before release. Input requests contain only
`schema_version`, `operation: correct`, `id`, `input`, `active_group`, `enabled`,
and `rules`; expected outputs and reasons are not sent to the adapter.

Each output line must contain exactly `schema_version: 1`, matching `id`, and
`text`. Fail on wrong bytes, omitted/extra/reordered replies, malformed JSON,
nonzero process exit, or the 30-second batch deadline. Do not call a fake adapter
an engine pass. Record failure output; successful reports are written only after
all requested gates pass, so use a fresh report path each run.

## Performance gate

```sh
python3 tests/local_corrections_harness.py --write-benchmark-workloads /tmp/foil-correction-workloads.json
```

This emits fixed-seed input requests (no expected outputs) for 500 rules/10 KiB and
1,000 rules/64 KiB. Shared-prefix aliases, hits, and misses are generated by
construction; their output SHA-256 oracle is computed separately in the harness.

The future in-process Swift benchmark adapter must record 50 fresh rule compilations,
50 cold controller calls, and 1,000 warmed calls per workload, under Release, at
`TranscriptionController.processTranscriptOrRaw`. Keep output verification outside
the timed interval, but verify every iteration, and fail immediately on mismatch.
Record raw arrays, exact build/configuration/model-free boundary, hardware, OS,
commit, and seed 20260914 in the schema checked by `validate_benchmark`.

Pass a real report to `--benchmark-report`. Warm normal budgets are p95 <= 10 ms,
p99 <= 25 ms; maximum-size p95/p99 <= 100 ms. Percentiles use nearest rank. Cold
compile/controller samples are reported separately, not mislabeled warm or hidden.
Actual cold-budget selection and Apple Silicon/Intel claims require measurements.
The validator rejects bad counts, nonfinite/negative timing, wrong output digests,
wrong configuration/boundary, and slow tails. Its unit tests use explicitly fake
reports solely to verify these checks; no production speed claim follows.

The existing controller baseline has no local engine to compile or time. Its
XCTest attachment is deliberately a different schema and **cannot** satisfy this
Release performance gate. Inspect actual adapter instrumentation in T1; a timing
report's assertion about its own boundary is not independent proof.

## Existing-app baseline

```sh
python3 scripts/run-local-corrections-baseline.py
```

The script makes a private test checkout, changes the test host bundle ID and
Application Support namespace, disables Sparkle startup in that copy only,
and records the isolation-only patch. Normal product naming is preserved so
branding-sensitive baseline assertions remain meaningful. It never installs or replaces Foil. Tests
continue to use the unchanged processing source. Existing XCTest hooks are
DEBUG-only, so this baseline uses Debug. An attempted Release baseline is a
diagnostic compile check, not a way to claim a Release engine measurement.

The selected suites cover controller routing/raw/cleanup/fallback/retry, History
privacy/recovery, vocabulary persistence/group resolution, and simulated queue
delivery. They do not paste into a real target. A dedicated desktop cross-app run,
independent holdout review, and production adapter/performance remain separate
gates; see the evidence receipt for actual results and outstanding work.
