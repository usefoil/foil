# T002 Plan Notes

Wrote `docs/superpowers/plans/2026-06-19-transcript-cleanup-formatting.md` using the repo's existing superpowers implementation-plan format because the requested `superpowers:writing-plans` skill is not installed in this Codex session.

The plan covers the approved spec through five implementation tasks:

- cleanup prompt model and AppState persistence
- controller/service cleanup request routing and independent cleanup API-key resolution
- Settings cleanup-formatting UI, prompt reset, preferred terms editor, and routing copy
- privacy, diagnostics, fallback warning, and final-text-only history proof
- final verification and spec audit

Remaining risks for Judge:

- Verify that allowing Groq cleanup for non-Groq STT is acceptable as the implementation of the spec's explicit cloud-cleanup routing requirement.
- Verify that the plan's UI-test command support is narrow enough and does not replace production UI behavior.
