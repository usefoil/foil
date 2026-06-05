# Foil iOS Real Dictation v0.3

## Objective

Replace the proven fake-transcript iOS prototype path with the first real
dictation loop: record audio in the containing app, transcribe through Groq
Whisper, persist the transcript into the App Group snapshot, and insert it from
Foil Keyboard into a target app on iPhone.

## Original Request

After proving the v0.2 keyboard shell and insertion/reset path on a physical
iPhone, implement the next slice: real dictation rather than fake transcript
handoff.

## Goal Oracle

`Foil iOS v0.3 is true when a known spoken phrase can be recorded in the
containing app, transcribed through the configured Groq provider, surfaced as a
ready transcript in the keyboard, inserted into Notes on the physical iPhone,
and cleared from the App Group snapshot after insertion.`

## Non-Goals

- Do not redesign the keyboard architecture or App Group bridge unless the real
  dictation loop cannot work with the current shape.
- Do not remove the fake transcript URL/test fixture; it remains useful for
  sterile keyboard insertion tests.
- Do not commit API keys, raw private transcripts, personal Notes content, JWTs,
  provisioning profiles, or private accessibility trees.
- Do not broaden into full TestFlight distribution unless the local/device proof
  passes first.

## Canonical Board

Machine truth lives at:

`docs/goals/ios-real-dictation-v0.3/state.yaml`

## Run Command

```text
/goal Follow docs/goals/ios-real-dictation-v0.3/goal.md.
```
