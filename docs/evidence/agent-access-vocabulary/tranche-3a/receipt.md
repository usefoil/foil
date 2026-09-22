# Tranche 3A — Vocabulary catalog foundation

Date: 2026-09-22

## Scope

This tranche adds the version-2 catalog schema, atomic store, legacy-source
fingerprinting, migration validation, and applied-proposal receipt ledger. It does
not activate migration in `AppState` or expose proposal apply. Coordinator and UI
wiring remain in Tranche 3B.

## Evidence

Claim: Existing vocabulary metadata and schema-v1 local rules can be copied into one
catalog without changing IDs, timestamps, order, Unicode bytes, enabled flags, case
sensitivity, or scope.

Strongest realistic failure mode: migration silently normalizes a phrase or
timestamp, reorders entries, or changes a legacy source while creating the catalog.

Evidence: `VocabularyCatalogStoreTests.testMigrationPreservesMetadataRuleBytesOrderAndFlagsWithoutTouchingLegacySources`
asserts complete model equality, UTF-8 byte equality for canonically distinct Unicode,
timestamp equality, rule order and flags, compiled correction behavior, and
byte-identical legacy files. The focused suite passed 13/13 at
`/tmp/Foil-VocabularyCatalogStore-6.xcresult`.

Claim: migration and later catalog saves fail closed at write, schema, revision, and
downgrade boundaries.

Strongest realistic failure mode: a partial staged write or failed commit becomes the
active catalog, a stale writer overwrites a newer revision, or a previous Foil version
edits legacy state and current Foil silently discards one side.

Evidence: focused tests inject a partial staged write and a failed rename, verify the
catalog is absent or byte-identical, reject stale and same-revision-tampered snapshots,
reject revision overflow, reject corrupt/future legacy and v2 schemas, and detect both
semantic and byte-only legacy edits via SHA-256 fingerprints. Legacy sources and the v2
catalog are asserted byte-identical after each rejection. The store stages in the
destination directory, creates the stage file as mode `0600`, synchronizes it, and uses
POSIX `rename` as the single commit boundary.

Claim: the catalog cannot persist metadata and linked executable rules that disagree.

Strongest realistic failure mode: a correction displays `Supabase` while its linked
rule executes a different replacement after migration or save.

Evidence: `VocabularyCatalogStoreTests.testLinkedRuleDivergenceFailsBeforeMigrationOrSave`
proves mismatched source/replacement bytes are rejected before the first catalog write
and before a later revision replaces valid bytes. `LocalCorrectionEngine.compile`
also runs before every migration/save and when loading persisted catalogs.

Claim: the foundation does not regress current vocabulary and local-correction
behavior before Tranche 3B activates it.

Strongest realistic failure mode: adding the schema or `Sendable` conformance breaks
the current AppState persistence and reconciliation paths.

Evidence:

- Focused compatibility run: 215 passed, 0 failed across
  `VocabularyCatalogStoreTests`, `LocalCorrectionStoreTests`, and `AppStateTests` at
  `/tmp/Foil-VocabularyCatalog-Compatibility-2.xcresult`.
- Full `make test`: 937 passed, 4 skipped, 0 failed at
  `/Users/jeremywatt/Library/Developer/Xcode/DerivedData/Foil-bbvtfwpscxqyrjboqavcznvrubcc/Logs/Test/Test-Foil-2026.09.22_08-47-57--0700.xcresult`.
- `make build-warnings-as-errors`: `BUILD SUCCEEDED`.
- `plutil -lint Foil.xcodeproj/project.pbxproj`: `OK`.
- `git diff --check`: clean.

Independent review found two fail-closed defects before closeout: the staging file
could briefly inherit broader permissions, and `Int.max` revision input could trap
on increment. The implementation now creates the stage as `0600` inside a `0700`
directory and rejects revisions that cannot be incremented. The focused suite covers
the overflow case and proves the persisted catalog remains byte-identical.

## Residual risk / follow-up

The store is intentionally dormant in this tranche. Tranche 3B must add the
main-actor coordinator, activate migration during AppState startup, surface the
legacy-fingerprint reconciliation state, and route every existing vocabulary/local
rule mutation through one catalog save before proposal apply is enabled.
