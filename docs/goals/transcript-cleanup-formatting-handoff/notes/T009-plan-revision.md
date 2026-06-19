# T009 Plan Revision

Revised `docs/superpowers/plans/2026-06-19-transcript-cleanup-formatting.md` after T003 rejected the first version for conditional proof steps.

Changes:

- Removed redundant conditional guidance after the final-text-only history test snippet.
- Replaced fallback-warning ambiguity with exact instructions for:
  - `FoilTests/TranscriptionControllerTests.swift` raw fallback and `cleanupFailed` assertions.
  - `Foil/UITestingController.swift` `seedCleanupFallbackWarning` app command.
  - `FoilUITests/FoilUITests.swift` visible warning test.
  - `Foil/FoilApp.swift` production warning copy alignment.

Verification:

- Placeholder scan had no matches.
- `git diff --check -- docs/superpowers/plans/2026-06-19-transcript-cleanup-formatting.md` passed.
