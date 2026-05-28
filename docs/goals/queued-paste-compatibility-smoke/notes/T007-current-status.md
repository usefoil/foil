# T007 Current Status

## Result So Far

in_progress

Added a guarded `--automation-smoke` queued-paste hook and a local Swift driver for real-target queued delivery.

## Evidence

Command:

```sh
ALLOW_LOCAL_QA_SKIP=1 make test-queued-paste-compatibility
```

Artifact:

- `/tmp/foil-queued-paste-compatibility-20260528-043456`
- `/tmp/foil-queued-paste-compatibility-20260528-044803`

Observed:

- The new hook enqueued real-target queued items for TextEdit and Chrome.
- The new hook delivered queued items through `QueuedPaste.deliver` and `PasteController.pasteQueued`.
- Unavailable-target fallback passed: after TextEdit quit, delivery produced clipboard fallback and the clipboard contained the queued text.
- TextEdit and Chrome delivery did not land in this desktop session. Diagnostics show `/Applications/Foil.app` is `accessibilityTrusted=false`; Foil captured app/pid but no AX window and command-posted paste did not reach the target fields.
- A rerun on 2026-05-28 reproduced the same queued-delivery failures and fallback pass. `make prepare-local-permissions-qa-check` then failed because the installed app bundle id is `com.neonwatty.Foil`, but `codesign` reports identifier `Foil`, ad-hoc signing, and no team id.

## Current Blocker

The remaining completion proof requires reinstalling `/Applications/Foil.app` with a trusted signing identity, refreshing/granting Accessibility and possibly Input Monitoring for that installed app identity, then rerunning:

```sh
ALLOW_LOCAL_QA_SKIP=1 make test-queued-paste-compatibility
```

This is not marked complete because the TextEdit and browser queued-delivery rows are still failing.
