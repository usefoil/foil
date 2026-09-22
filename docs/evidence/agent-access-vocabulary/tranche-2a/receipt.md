# Agent Access Vocabulary Tranche 2A Evidence

Date: 2026-09-21

Scope: versioned proposal models and the inert, brand-scoped atomic proposal store.
This slice does not expose submission routes or review UI.

## Durable and idempotent persistence

Claim: a valid proposal is persisted once, survives relaunch, and simultaneous
replays or distinct submissions cannot overwrite one another.

Strongest realistic failure mode: concurrent calls pass the same pre-write check,
create duplicate receipts, or replace proposals already on disk.

Evidence: `VocabularyProposalStoreTests` exercises 40 simultaneous submissions of
one request and 30 simultaneous distinct requests. It proves one original receipt,
39 byte-preserving replays, 30 retained IDs, and matching revisions. The focused
command passed 21 tests:

```sh
xcodebuild test -scheme Foil -configuration Debug -destination 'platform=macOS' \
  -only-testing:FoilTests/VocabularyProposalContractTests \
  -only-testing:FoilTests/VocabularyProposalStoreTests \
  -resultBundlePath /tmp/Foil-Tranche2A-Focused-7.xcresult
```

Residual risk / follow-up: serialization is intentionally guarded inside one store
instance owned by Foil's single app process. Tranche 2B must keep one controller-owned
store and prove the HTTP race through the live router.

## Fail-closed storage

Claim: malformed, future-version, tampered, conflicting, over-capacity, and failed
writes do not replace accepted proposal state.

Strongest realistic failure mode: valid-looking JSON with a changed correction or
digest loads successfully, or an error path advances the revision after a partial
operation.

Evidence: focused tests compare pre/post bytes for request-ID conflicts, queue-full,
invalid envelopes, injected write failure, invalid digests, payload tampering,
corrupt JSON, and future schemas. Reload recomputes every canonical request digest.
Snapshot tokens must be lowercase SHA-256 digests, which prevents callers from
putting raw Vocabulary text into that metadata field. The persisted file permission
test verifies mode `0600`.

Residual risk / follow-up: live scope validity, request-size limits, matcher
conflicts, diagnostics, and socket cancellation belong to Tranche 2B because 2A has
no submission route.

## Wire stability and regression safety

Claim: proposal requests and receipts have a versioned snake-case contract, and the
new persistence layer does not change current matcher or app behavior.

Strongest realistic failure mode: receipt encoding exposes internal request hashes
or snapshot tokens, Unicode-equivalent retries fork, or adjacent app code stops
building.

Evidence:

- Contract tests verify the documented request shape, default case sensitivity,
  canonical Unicode/whitespace hashing, meaningful-content differences, receipt
  fields, and separate Foil/Foil Dev paths.
- `make test` passed 912 tests with 4 skips and 0 failures. Result bundle:
  `/Users/jeremywatt/Library/Developer/Xcode/DerivedData/Foil-fhltyouoqrthjahckcgclpmqavpe/Logs/Test/Test-Foil-2026.09.21_16-53-59--0700.xcresult`.
- `make build-warnings-as-errors` passed.
- `make test-local-correction-engine` passed all 18 harness tests and the 150-case
  production-engine gate.

Residual risk / follow-up: no user-visible workflow is claimed by this foundation
slice. Tranche 2B supplies the routes, review surface, and end-to-end privacy proof.
