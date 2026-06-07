# T003 Worker - Live Transcription Proof

## Result

Done.

## Summary

Ran a physical build-10 live transcription proof on `iPhone-preview`. The
successful path used Foil app controls to record and transcribe a repeated
sterile phrase, then inserted the provider-produced transcript into a sterile
Notes editor through Foil Keyboard.

No product code changes were needed.

## Changed Files

- `docs/goals/ios-v0.19-live-transcription-proof/notes/T003-worker.md`
- `docs/goals/ios-v0.19-live-transcription-proof/notes/receipts/*.json`
- `docs/goals/ios-v0.19-live-transcription-proof/state.yaml`

## Attempt Notes

- Attempt 1 reached a complete transcript but did not match the intended phrase.
  The cause was audio routing: macOS output was set to AirPods, so the phone was
  not hearing the laptop speakers clearly.
- Before attempt 2, macOS output was switched to `MacBook Pro Speakers`, output
  volume was raised to 82, and AirPods were disconnected.
- Attempt 2 used macOS text-to-speech with the repeated sterile phrase:
  `foil audio smoke test. foil audio smoke test. foil audio smoke test.`

## Evidence

- `status-live.json` proves WDA was reachable at `http://192.168.1.40:8100`
  with WDA project present.
- `app-group-before-attempt2.json` proves the App Group started
  `phase=idle`, `hasTranscript=false`.
- `attempt2-foil-before-record.json` proves the Foil app had a record button and
  Groq key configured.
- `attempt2-foil-after-record-start.json` proves the Foil app entered recording
  state.
- `attempt2-foil-after-record-stop.json` proves the Foil app saved a recording
  and exposed the transcribe action.
- `attempt2-foil-after-transcribe.json` proves the Foil app reported Ready for
  keyboard, Groq transcript ready, a transcript review body, and Transcript
  pending.
- `attempt2-app-group-after-transcribe.json` proves App Group
  `phase=complete`, `hasTranscript=true`, `transcriptLength=68`, with only
  transcript hash/length recorded.
- `notes-before-insert.json` proves Foil Keyboard was visible in Notes and
  Insert latest was enabled.
- `notes-after-insert.json` proves Insert latest became disabled and the sterile
  phrase appeared exactly three times in the Notes text value.
- `app-group-after-insert.json` proves App Group returned to `phase=idle`,
  `hasTranscript=false` after insertion.
- `app-group-cleanup.json` proves an explicit final reset/readback also ended
  `phase=idle`, `hasTranscript=false`.

## Privacy Boundary

- Raw WDA source was kept under `/tmp` and not committed.
- Receipts record hashes, counts, booleans, identifiers, and lengths.
- No provider key, raw private note content, Messages content, or screenshots
  were committed.

## Residual Risk

Notes already had a sterile editor with Foil Keyboard visible, so the run did
not need to create a new note via the New Note button. The pre-insert receipt
still proved the target was a Notes editor with Foil Keyboard visible and Insert
latest enabled; the post-insert receipt proved the sterile phrase count in that
editor.
