# T011 Plan Revision

Added exact cleanup-off no-request proof to `docs/superpowers/plans/2026-06-19-transcript-cleanup-formatting.md`.

Changes:

- Added `testCleanupOffDoesNotSendCleanupRequest` to the planned `FoilTests/TranscriptionControllerTests.swift` additions.
- Updated the focused controller test command to include that test.
- Preserved existing routing/key and prompt/preferred-term tests.

Verification:

- Placeholder scan had no matches.
- `git diff --check -- docs/superpowers/plans/2026-06-19-transcript-cleanup-formatting.md` passed.
- Direct `rg` confirmed the plan contains the test name, focused command entry, and final audit requirement.
