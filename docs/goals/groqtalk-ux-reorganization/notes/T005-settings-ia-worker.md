# T005 Worker Receipt

Result: done

## Summary

Reorganized Settings into the approved information architecture without changing preference storage.

Changes:

- Added an Advanced tab.
- Renamed Paste to Paste & Clipboard.
- Renamed Privacy to Privacy & Storage.
- General now contains launch/login, notifications, sound effects, floating status, and updates.
- Recording now contains shortcut, custom shortcut, hold/toggle mode, audio format, and input device.
- Transcription now starts with provider, then credentials/connection test, then model/speech language, then cleanup.
- Moved speech language from Recording to Transcription.
- Moved Keep final text on clipboard from General to Paste & Clipboard.
- Split Privacy & Storage into Local Data, Storage, and Clear Local Data sections.
- Moved debug Mock transcription into Advanced.

## Verification

Passed:

```text
xcodebuild build -scheme GroqTalk -configuration Debug -destination 'platform=macOS'
```

Result:

```text
** BUILD SUCCEEDED **
```

Source checks confirmed:

- `Paste & Clipboard` tab exists.
- `Privacy & Storage` tab exists.
- `Advanced` tab exists.
- provider picker appears before credentials.
- `Speech language` appears in Transcription.
- `settings.keepClipboardToggle` appears in Paste & Clipboard.
- `settings.mockToggle` appears in Advanced.
- destructive clear actions are under `Clear Local Data`.

## Notes

No visual Settings receipt was captured in this slice; visual verification remains queued for T007.
