# T999 Final Audit - Host-App Matrix

## Decision

Complete.

## Outcome

The v0.20 oracle is satisfied as a matrix expansion with receipt-backed
pass/block outcomes for additional sterile targets:

- Safari local single-line input: pass.
- Mail blank compose draft: blocked by unavailable Mail bundle through sterile
  `mailto:` path.
- Calendar blank new-event title: blocked by lack of a verified sterile path to
  a blank new-event sheet without risking private calendar content.
- Foil iOS secure-field rejection fallback: blocked by Diagnostics disclosure
  not expanding through WDA in this run.

This is intentionally not a claim that Mail or Calendar insertion works. It is a
committed compatibility matrix with exact blockers and one new passing target,
which matches the board's pass/block/fail oracle and gives the next boards clear
work to unblock.

## Requirement Audit

- At least three additional sterile targets recorded:
  `docs/ios-keyboard-host-app-matrix.md` records four v0.20 rows.
- Pre-insert readiness for pass rows:
  `safari-single-before-insert.json` proves Foil Keyboard root and Insert latest
  enabled before Safari insertion.
- Post-insert exact-once proof for pass rows:
  `safari-single-after-insert.json` proves Insert latest disabled and the
  sterile Safari value count is exactly `1` in value attributes.
- App Group cleanup proof:
  `safari-single-app-group-after-insert.json`, `safari-single-cleanup.json`, and
  `foil-secure-cleanup.json` prove idle/readback cleanup for touched App Group
  state.
- Expected rejection/block proof:
  `mail-compose-blocker.json`, `calendar-new-event-blocker.json`, and
  `foil-secure-blocker.json` record exact blocker conditions rather than
  pretending unsupported rows passed.
- Privacy boundary:
  raw WDA source stayed in `/tmp`; committed docs/receipts contain hashes,
  booleans, counts, command outcomes, and blocker reasons, not raw private app
  content.

## Strongest Realistic Failure Mode

The matrix could look broader than it really is by treating blocker rows as
working compatibility.

Evidence against that failure:

- The matrix explicitly labels Mail, Calendar, and Foil secure rejection as
  blocked, with follow-up conditions.
- The only v0.20 row labeled pass is Safari local single-line input, and it has
  pre-insert, post-insert, exact value-count, App Group idle, and cleanup
  receipts.
- The final matrix describes Mail/Calendar as future rows requiring installed or
  operator-provided sterile surfaces.

## Verification

- GoalBuddy state checker passes after marking the board done.
- Receipt assertion script passes for WDA readiness, Safari pre/post/cleanup,
  Mail blocker, Calendar blocker, Foil secure blocker, and cleanup.
- All JSON receipts parse.
- Secret scan is quiet.
- Raw-content scan returns only privacy-boundary prose, not raw WDA XML/source
  or private host-app values.
- `git diff --check` passes.
- Automation cleanup check via `ps` finds no remaining WDA/server processes
  from this run.
