# Queued Paste Compatibility Smoke

This runbook records the issue 159 compatibility smoke for queued paste. It is
intentionally local-only because target capture, app activation, Accessibility,
and browser text-entry behavior depend on the active macOS desktop session.

## Scope

This smoke is for the queued-paste MVP only:

- Verify that target identity is app/window based, not a stored screen point.
- Cover TextEdit and one browser text-entry target.
- Record fallback or unavailable-target behavior.
- Capture follow-ups before adding a global queued-paste delivery hotkey.

Out of scope:

- Global queued-paste hotkey delivery.
- Overlapping recording or overlapping transcription architecture.
- Release packaging or distribution checks.

## What Must Be Recorded

Each target row must record:

- Target app and target surface.
- Captured identity signal: app name, pid, and window/title/window ID when
  observable.
- Whether the transcript was queued before delivery.
- Delivery action used: Paste Next or Drain Queue.
- Whether text landed in the intended target app/window.
- Whether the app returned focus as expected.
- Fallback behavior for unavailable targets, or the exact reason fallback could
  not be exercised.
- Evidence: command, log path, screenshot path, or manual transcript notes.

## Local Command

Run:

```sh
make test-queued-paste-compatibility
```

This command runs the available local target-identity gates and writes logs under
`/tmp/foil-queued-paste-compatibility-*`. It does not run browser automation by
default, and it does not run the older `make test-cross-app` gate by default.
Use `scripts/run-queued-paste-compatibility-smoke.sh --include-browser` for the
browser queued-paste row on an idle desktop. Use
`scripts/run-queued-paste-compatibility-smoke.sh --include-cross-app` only where
the older Chrome/Terminal integration gate is acceptable.

Make targets:

- `make test-queued-paste-compatibility`: safe default; skips browser automation.
- `make test-queued-paste-compatibility-browser`: includes the browser queued-paste row.
- `make test-queued-paste-compatibility-cross-app`: includes the browser queued-paste row and the older cross-app Chrome/Terminal gate.

Important: the command includes a bounded real-target queued-paste automation
hook, but it still depends on the local desktop permission state. If TextEdit or
browser delivery fails while Foil logs `accessibilityTrusted=false`, refresh or
grant Accessibility and Input Monitoring for `/Applications/Foil.app`, then
rerun the smoke. Record failures as compatibility evidence rather than treating
clipboard contents alone as success.

## Manual Queued-Paste Procedure

Use disposable targets only.

1. Install and launch the debug or installed Foil app.
2. Enable `Queue transcriptions for later paste` in Experimental settings.
3. Enable mock transcription if using a debug build; otherwise use a short real
   recording.
4. Open the target app and place the cursor in the target text field.
5. Start and stop a transcription while the target app/window is frontmost.
6. Confirm Foil shows `Transcript queued`.
7. Move focus away from the target app/window.
8. Use Foil's `Paste Next` action.
9. Confirm the text lands in the original target app/window.
10. Record app/window identity behavior and evidence in the matrix.

For fallback:

1. Repeat the same capture and queue steps.
2. Close the target window or quit the target app before `Paste Next`.
3. Use `Paste Next`.
4. Record whether the item becomes manual-paste/fallback, whether text is copied
   to the clipboard, and the user-visible recovery path.

## Compatibility Matrix

| Target | Procedure | Target identity evidence | Queued evidence | Result | Evidence / notes |
| --- | --- | --- | --- | --- | --- |
| TextEdit disposable document | Automation hook plus prerequisite command `ALLOW_LOCAL_QA_SKIP=1 make test-queued-paste-compatibility` | Prerequisite evidence from `tests/test_async_paste.swift`: captured `TextEdit pid=26348` with a window element and pasted into `AsyncPasteTestA.txt`, not the current `AsyncPasteTestB.txt`; `tests/test_skylight_paste.swift` captured `TextEdit wid=123587` and pasted while Finder stayed frontmost. Foil's installed-app automation captured `TextEdit pid=29687` but no AX window because `accessibilityTrusted=false` for `/Applications/Foil.app` in this session. | `tests/test_queued_paste_compatibility.swift` triggered `QueuedPaste.enqueue: status=pending target=TextEdit`, then `QueuedPaste.deliver` and `automation queued smoke: deliver next result=original app command posted`. | Failed in this desktop session: queued item delivered according to Foil, but text did not land in the TextEdit target. | Artifact: `/tmp/foil-queued-paste-compatibility-20260528-043456/queued-real-targets.log`. Follow-up: refresh/grant Accessibility/Input Monitoring for `/Applications/Foil.app`, then rerun. |
| Browser text field | Automation hook plus prerequisite command `ALLOW_LOCAL_QA_SKIP=1 make test-queued-paste-compatibility` | Prerequisite evidence from `make test-cross-app`: Chrome textarea target passed, with text reaching the captured textarea and frontmost after paste reported as `Google Chrome`. Foil's installed-app automation captured `Google Chrome pid=30174` but no AX window because `accessibilityTrusted=false` for `/Applications/Foil.app` in this session. | `tests/test_queued_paste_compatibility.swift` triggered `QueuedPaste.enqueue: status=pending target=Google Chrome`, then `QueuedPaste.deliver` and `automation queued smoke: deliver next result=original app command posted`. | Failed in this desktop session: queued item delivered according to Foil, but text did not land in the Chrome textarea. | Artifact: `/tmp/foil-queued-paste-compatibility-20260528-043456/queued-real-targets.log`. Follow-up: refresh/grant Accessibility/Input Monitoring for `/Applications/Foil.app`, then rerun. |
| Closed/unavailable target | Automation hook in `tests/test_queued_paste_compatibility.swift` | Captured TextEdit target before quitting TextEdit. | `QueuedPaste.enqueue: status=pending target=TextEdit`, followed by target process termination before delivery. | Passed: delivery returned clipboard fallback and the clipboard contained the queued transcript text. | Artifact: `/tmp/foil-queued-paste-compatibility-20260528-043456/queued-real-targets.log`. |

## 2026-05-28 Local Evidence

Command:

```sh
ALLOW_LOCAL_QA_SKIP=1 make test-queued-paste-compatibility
```

Result: pass with explicit local skip. The command wrote artifacts to
`/tmp/foil-queued-paste-compatibility-20260528-042455`.

Observed:

- `make test-paste-real` built and installed `/Applications/Foil.app`, posted
  the automation mock transcription request, observed the async paste path,
  exercised production `TextInserter.insertAsync`, and avoided the UI-test paste
  bypass.
- The installed-app TextEdit gate skipped because this desktop session did not
  expose the target AX window to the app process.
- `make test-cross-app` passed its TextEdit async paste, SkyLight background
  paste, Terminal, and Chrome textarea checks.
- VS Code was skipped because it is not installed.
- Notes was skipped by design to avoid mutating persistent Notes data.

Conclusion: target app/window capture and browser text-field paste mechanics
have local prerequisite evidence. The oracle still needs a manual real-target
queued-paste row or a later product test hook because the current queued
automation path uses a synthetic Foil target.

## Follow-Up Rules

Create a follow-up when:

- Text reaches the clipboard but not the intended app/window.
- The queue cannot distinguish target unavailable from paste failure.
- Browser text fields need app-specific activation or focus handling.
- A fully automated real-target queued smoke needs a product-only test hook.

Do not fold hotkey delivery or overlapping transcription into this tranche.
