# Intake Notes

## Source Design

- `docs/superpowers/specs/2026-05-19-foil-ux-reorganization-design.md`

## Approved Direction

- Hybrid UX backbone: lean menu bar control center, guided setup hub, reorganized Settings.
- Menu bar ready state: session hero, one primary action, record controls, compact last result, utility footer, setup summary only when needed.
- Setup: first-run context before permission prompt path, integrated API key action, app-level permission refresh/polling, visible per-step status.
- Settings: General, Recording, Transcription, Paste & Clipboard, Privacy & Storage, Advanced.
- Testing: prioritize setup correctness first, avoid XCUITest unless explicitly authorized, include visual verification.

## Initial Board Intent

Use Scout/Judge/Worker sequencing so implementation starts from a migration map, then proceeds through bounded slices with measurable acceptance criteria and verification receipts.
