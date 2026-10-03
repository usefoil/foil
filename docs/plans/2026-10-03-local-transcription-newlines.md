# Plan: Remove whisper.cpp segment newlines from pasted dictation

Status: implemented and verified on 2026-10-03. Base: `origin/main` at `30ed06c` on branch
`codex/transcription-newlines`.

## Problem and cause

Foil requests `response_format=text` for transcription. The pinned whisper.cpp
server appends `\n` after every recognition segment in that format. Foil removes
whitespace only at the beginning and end of the response, so internal segment
breaks reach local corrections, optional Cleanup, history, and paste. A segment
boundary can fall mid-sentence. The existing `--no-timestamps` option on Foil's
external local server does not change that text serializer.

Source: [the pinned server's `output_str` implementation](https://github.com/ggml-org/whisper.cpp/blob/927cfce34f31707e17f2bff35c349632fb9e2c3a/examples/server/server.cpp#L454-L470).

This plan addresses the segment separators in Foil's two named whisper.cpp
routes: managed local and the built-in `Local whisper.cpp` preset. It leaves
Groq, OpenAI, and custom OpenAI-compatible providers' line breaks alone.

## User-visible contract

| Provider response | Pasted text |
| --- | --- |
| `One sentence.\n Another sentence.` | `One sentence. Another sentence.` |
| `A thought\r\n continues here.` | `A thought continues here.` |
| `First paragraph.\n\nSecond paragraph.` | `First paragraph.\n\nSecond paragraph.` |
| `First item\n second item` from a cloud or custom provider | Unchanged |

For the two whisper.cpp routes, join a **single** CR, LF, or CRLF segment break
and adjacent horizontal spaces/tabs into one space. Preserve runs of two or
more line breaks as a paragraph break, normalized to `\n\n`. Preserve all other
characters and interior whitespace. The service's existing outer trim remains
in effect. Apply this before local corrections and Cleanup so every subsequent
stage sees the same readable transcript. When Cleanup fails, paste the joined
transcript rather than restoring the segment breaks.

Keep the decoded provider text (after the service's existing outer trim) in the
in-memory `originalText` path for last-session recovery. Persist only the final
pasted text, as history does today. Do not write transcript content to
diagnostics; a count of joined breaks is enough for troubleshooting.

This rule cannot distinguish a server segment separator from an intentional
single line break inside a plain-text response. That is the known v1 tradeoff.
The rule preserves blank-line paragraph breaks. Cleanup can infer readable
paragraph structure, but it cannot recover the exact position of an intentional
single line break after joining. Users who need the provider's exact output can
copy the original transcript from last-session recovery or use a custom
provider route that does not opt into joining. Do not silently apply the rule to
all providers.

## Implementation sequence

1. **Represent the policy explicitly.** Add a small line-break policy to
   `TranscriptionProvider` in `Foil/TranscriptionService.swift`, defaulting to
   preserve. Set join-segments for `TranscriptionProvider.managedLocal` and for
   the built-in local preset constructed in `Foil/AppState.swift`. Keep the
   custom OpenAI-compatible route at preserve, even when its URL is localhost;
   URL matching is not a reliable signal of whisper.cpp behavior. Add focused
   provider-construction assertions in `FoilTests/AppStateTests.swift` and
   `FoilTests/TranscriptionServiceTests.swift`.

2. **Create a pure formatter at the controller boundary.** In
   `Foil/TranscriptionController.swift`, implement a small formatter that takes
   the decoded provider string and policy and returns the formatted string plus
   a replacement count. Handle `\n`, `\r\n`, and `\r`; do not alter punctuation,
   Unicode characters, or spaces away from a line break. Keep it independent of
   provider HTTP parsing and paste delivery.

3. **Use it on every transcription outcome.** In both `transcribe` and
   `retryTranscription`, capture the provider's decoded text, detect no-speech,
   then format it before calling `processCapturedTranscript`. Pass the provider
   text separately as `originalText`; update all result branches (raw, local
   correction, cleanup success, cleanup failure, and correction-size fallback)
   so their final text uses the formatted input and their original text remains
   the provider response. Apply the same policy to the onboarding practice
   callback. Mock transcription remains unchanged. History reclean already
   operates on stored final text and should not format it a second time.

4. **Make the raw-mode copy accurate.** `Foil/TranscriptProcessingMode.swift`
   currently promises to paste text exactly as returned by transcription.
   Change that description to say raw mode skips AI Cleanup and that Foil joins
   local whisper.cpp segment breaks for readability. No new setting, model
   parameter, server patch, or Cleanup prompt change is needed for the first
   version. If users need explicit single line breaks, revisit a structured
   `verbose_json` segment response or an opt-out setting with a separate
   product decision.

## Verification and failure-oriented evidence

| Realistic failure | Proof to collect |
| --- | --- |
| A break like the reported example remains in paste | Formatter unit cases and a controller transport fixture containing `model.\n It's`; assert delegate `text` is `model. It's` and `originalText` still contains the newline. |
| Paragraphs, Unicode, or punctuation are damaged | Cases for CR/LF/CRLF, blank lines, leading/trailing trim, apostrophes, emoji, tabs away from breaks, and unchanged no-break text. Compare UTF-8 where exact bytes matter. |
| A cloud or custom provider changes unexpectedly | Controller tests with the same multiline fixture for Groq, OpenAI, and custom OpenAI-compatible providers; assert byte-for-byte preservation. Check policy after switching presets. |
| Cleanup failure or local-correction fallback returns the bad line breaks | Focused controller tests that force each fallback and compare final text with `originalText`. Assert no second provider request occurs in raw mode. |
| Managed local and external local behave differently | Assert policy assignment for both routes, then run a longer real local recording against each available route. Capture the server response and final text in an ephemeral QA fixture, with no transcript in permanent logs. |
| History, retry, or paste diverges from the callback | Assert retry and practice callbacks; inspect history's saved final text and in-memory original. Run a local end-to-end paste check and compare target text with the expected joined transcript. |

Run focused `xcodebuild test` rows for `FoilTests/TranscriptionControllerTests`,
`FoilTests/TranscriptionServiceTests`, and `FoilTests/AppStateTests`, followed by
`make test`, `make test-provider-qa`, and `make test-local-transcription-e2e` with
an available local server. Run `make test-cross-app` if the final paste path is
touched. The current short local audio fixture may not cross a Whisper segment
boundary, so it cannot alone prove the newline repair; add a deterministic
multiline response fixture and a longer real-audio check. Record skips and
hardware/runtime limits using `docs/acceptance-evidence.md`.

Before calling the implementation complete, compare a real provider response
with the controller's final text, inspect its pass-through into paste, and try
to falsify the paragraph-preservation and provider-isolation claims. If a pull
request is requested, run the required
`codex-pr-review-toolkit` gate against the resolved base, fix accepted findings,
and repeat until its high-confidence findings are clear before creating the PR.

## Implementation evidence

Claim: The two named whisper.cpp routes join segment line breaks before
corrections, Cleanup, and paste, while cloud and custom routes preserve their
internal line breaks.

Strongest realistic failure modes and evidence:

- **The server does not produce the assumed separator.** A 65.6-second
  synthetic dictation sent directly to Foil's pinned managed whisper.cpp helper
  returned HTTP 200, 1,013 transcript characters, and 14 internal newlines.
  Its first break followed “FOIL app.” while the dictated thought continued.
  The helper and test model came from this worktree's verified managed-runtime
  cache. The probe discarded its audio and transcript when it exited.
- **The app still delivers a break, or damages intentional paragraphs.**
  `FoilTests/TranscriptionControllerTests` covers the controller callback,
  practice, retry, cleanup-failure fallback, CR/LF/CRLF, blank lines, and
  byte-for-byte preservation under the other provider policy. The focused
  Xcode run passed 338 tests, with one skip and no failures; result bundle:
  `/tmp/foil-transcription-newlines-derived/Logs/Test/Test-Foil-2026.10.03_11-32-18--0700.xcresult`.
- **An adjacent provider or shared caller regresses.** `make test` passed
  949 tests, with four skips and no failures; result bundle:
  `~/Library/Developer/Xcode/DerivedData/Foil-btuhznhkaryhnactunuwgdoplzoq/Logs/Test/Test-Foil-2026.10.03_11-34-48--0700.xcresult`.
  `make test-provider-qa` passed all 11 UI cases; result bundle:
  `~/Library/Developer/Xcode/DerivedData/Foil-btuhznhkaryhnactunuwgdoplzoq/Logs/Test/Test-Foil-2026.10.03_11-36-59--0700.xcresult`.
- **The joined result is lost after the controller callback.** Direct inspection
  of `Foil/FoilApp.swift` shows the callback's `text` passed unchanged to
  `history.addSuccess`, `history.resolveRetry`, `pasteController.paste`,
  `pasteController.pasteDirectly`, and `queuedPasteQueue.enqueue`.
- **The paste target receives no text or the wrong window receives it.** The
  first two scripts in `make test-cross-app` passed against live TextEdit
  windows: delayed paste reached the captured window after focus moved, and
  background paste reached the captured TextEdit window while Finder stayed
  frontmost. The third script stalled while AppleScript queried Terminal's
  front window and was interrupted; the full target did not pass.

Residual risk: A plain-text response does not identify whether a single line
break was an intentional user-requested break or a server segment separator.
The formatter preserves blank-line paragraphs, and the exact decoded provider
text remains available in last-session recovery. The external local server
end-to-end harness was not run because no external server was listening on its
default port; its controller path is covered by a deterministic transport
fixture, and the pinned managed server was exercised directly. An actual
cross-app paste of the long real-audio transcript was not performed; the
controller callback, unchanged paste pass-through, and the two completed
cross-app paste scripts are the current evidence for that final boundary. The
third `make test-cross-app` script remains a desktop automation follow-up; it
stalled in an AppleScript Terminal query rather than reporting an assertion
failure. The built menu bar app could not be attached to the computer-use UI
tool in this session, so an in-app long-audio paste check is also outstanding.
