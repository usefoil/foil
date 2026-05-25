# T001 Batch 1 Diagnostics Judge

## Decision

Batch 1 can start as written, but the first safe Worker slice should be the diagnostics foundation rather than the UI export surface.

The current code already has many `DiagnosticLog.write(...)` call sites across app launch, setup health, permissions, recording, transcription, paste routing, keychain, audio recorder, and UI test helpers. The missing foundation is centralized export/read/redaction behavior.

## Evidence

- `Foil/DiagnosticLog.swift` currently writes plain text to `/tmp/foil-diag.log`.
- `DiagnosticLog` is enabled in `DEBUG`, but in release only when `FOIL_DIAGNOSTICS=1`.
- There is no public API to read recent log lines or export a diagnostics report.
- There is no central redaction API or tests for secrets/user-content redaction.
- Existing call sites mostly avoid transcript text and audio content, but some diagnostic strings can include local file paths, app names, provider/model names, error strings, and byte counts.
- Existing lifecycle coverage is partial: launch/setup/permission/recording/transcription/paste paths have logs, but they are unstructured and not prepared as a user-attachable report.

## First Worker Slice

Objective: add a local diagnostics core that can safely collect, redact, and export recent logs without adding the final UI yet.

Allowed files:

- `Foil/DiagnosticLog.swift`
- `FoilTests/DiagnosticLogTests.swift`
- `Foil.xcodeproj/project.pbxproj`
- `docs/goals/follow-up-ux-diagnostics-sounds-browser-audio/notes/diagnostics-audit.md`

Verification:

- `xcodebuild test -project Foil.xcodeproj -scheme Foil -destination 'platform=macOS' -only-testing:FoilTests/DiagnosticLogTests`
- `make build-warnings-as-errors`
- `git diff --check`

Stop if:

- The implementation needs app UI, settings, menu commands, or files outside the allowed list.
- Redaction requirements become ambiguous for transcript text, clipboard contents, raw audio, API keys, or local paths.
- The implementation would send diagnostics outside the user's machine.
- Focused tests fail twice for unclear reasons.

## Rationale

This slice creates the proof boundary Batch 1 needs before adding UI: exported diagnostics must be locally readable, redacted, bounded, and testable. Once this foundation is in place, the next Worker can add structured lifecycle events and the user-facing export flow with less privacy risk.
