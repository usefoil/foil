# iOS Audio Reliability v0.5

## Original Request

Do the next iOS slice after v0.4: make weak transcript/audio handling more reliable.

## Outcome

Foil iOS rejects empty-ish or punctuation-only Groq transcripts before they become keyboard-insertable, keeps real speech transcripts available, and records a proof path for the noisy physical-phone audio fixture.

## Oracle

Focused iOS tests must prove transcript-quality gating rejects punctuation-only/empty transcripts and accepts real text. A physical or simulator smoke should prove the app still builds and the v0.4 weak transcript failure mode is addressed without breaking real transcript insertion.

## Constraints

- Use TDD: write failing test before production code.
- Keep changes narrow to transcript-quality gating and receipts.
- Do not print or commit Groq keys, App Store Connect keys, JWTs, or private phone content.
- Do not claim exact ASR quality from Mac speaker-to-phone microphone audio.

## Likely Misfire

The app could add nicer copy while still allowing `"."` or other punctuation-only provider output to become `Insert latest`, creating a false-positive transcript. The final audit must try to disprove that.

## Starter Command

`/goal Follow docs/goals/ios-audio-reliability-v0.5/goal.md.`
