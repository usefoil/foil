# T004 Worker Receipt

Result: done

## Summary

Simplified the menu bar ready-state layout.

Changes:

- Detailed setup panel now appears only when setup needs attention.
- Feedback panel now appears only when there is actual transient feedback, a captured target, clipboard feedback, or active async target context.
- Recording controls remain directly available in a dedicated Record section.
- Removed the normal menu-bar quick controls for durable preferences:
  - hotkey;
  - hold/toggle mode;
  - async paste;
  - keep final text on clipboard;
  - floating status;
  - cleanup mode;
  - debug mock transcription and simulation buttons.

## Verification

Passed:

```text
xcodebuild test -scheme Foil -configuration Debug -destination 'platform=macOS' -only-testing:FoilTests/AppStateTests
```

Result:

```text
Executed 105 tests, with 0 failures.
** TEST SUCCEEDED **
```

Additional source check:

```text
rg -n "menu\\.(hotkeyPicker|recordingModePicker|asyncPasteToggle|keepClipboardToggle|floatingStatusToggle|transcriptProcessingPicker|mockToggle|simulateSuccessButton|simulateFailureButton)|Quick Controls|Mock Transcription" Foil/MenuBarView.swift
```

Result: no matches.

## Notes

No visual receipt was captured in this slice because UI-test launch is intentionally deferred until the authorized regression/visual verification phase.
