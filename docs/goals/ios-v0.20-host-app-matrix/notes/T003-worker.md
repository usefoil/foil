# T003 Worker - Host-App Matrix Slice

## Result

Done.

## Summary

Executed the approved v0.20 host-app matrix slice on `iPhone-preview` using WDA
at `http://192.168.1.40:8100`.

Outcomes:

- Safari local single-line input: pass.
- Mail blank compose draft: blocked because the Mail app bundle was unavailable
  through the sterile `mailto:` path.
- Calendar blank new-event title: blocked before launch because there was no
  verified sterile path to a blank event sheet without risking private calendar
  content.
- Foil iOS secure-field rejection fallback: blocked because the Diagnostics
  disclosure containing `secure-rejection-field` could not be expanded through
  WDA element click or W3C coordinate tap.

## Evidence

- `status-wda.json` proves WDA was reachable and ready at
  `http://192.168.1.40:8100`.
- `safari-single-before-insert.json` proves Foil Keyboard root and Insert latest
  were visible in the Safari single-line fixture before insertion.
- `safari-single-after-insert.json` proves the sterile value appeared exactly
  once in value attributes and Insert latest became disabled.
- `safari-single-app-group-after-insert.json` proves App Group returned
  `phase=idle` after Safari insertion.
- `safari-single-cleanup.json` proves explicit final reset/readback idle.
- `mail-compose-blocker.json` records the WDA `mailto:` open failure without
  inspecting Mail source.
- `calendar-new-event-blocker.json` records the privacy stop before any Calendar
  source/screenshot was fetched.
- `foil-secure-stage.json` proves a pending transcript was staged for the
  fallback row; `foil-secure-blocker.json` records the first-party Diagnostics
  expansion blocker; and `foil-secure-cleanup.json` proves App Group cleanup
  idle.

## Privacy Boundary

- Raw WDA sources were kept under `/tmp` only.
- No Mail inbox, Calendar source, Messages source, screenshots, contacts,
  filenames, account metadata, provider keys, or private host-app content were
  committed.
- The Safari transcript strings were deliberately sterile fixtures.

## Residual Risk

This board expands the matrix with one additional passing insertion target and
three exact blockers. It does not yet prove Mail or Calendar insertion. Those
rows need either installed/configured sterile surfaces or operator setup before
they can be converted from blocked to pass/fail.
