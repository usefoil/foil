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

Observed:

- The new hook enqueued real-target queued items for TextEdit and Chrome.
- The new hook delivered queued items through `QueuedPaste.deliver` and `PasteController.pasteQueued`.
- Unavailable-target fallback passed: after TextEdit quit, delivery produced clipboard fallback and the clipboard contained the queued text.
- TextEdit and Chrome delivery did not land in this desktop session. Diagnostics show `/Applications/Foil.app` is `accessibilityTrusted=false`; Foil captured app/pid but no AX window and command-posted paste did not reach the target fields.

## Current Blocker

The remaining completion proof likely requires refreshing/granting Accessibility and possibly Input Monitoring for `/Applications/Foil.app`, then rerunning:

```sh
ALLOW_LOCAL_QA_SKIP=1 make test-queued-paste-compatibility
```

This is not marked complete because the TextEdit and browser queued-delivery rows are still failing.

