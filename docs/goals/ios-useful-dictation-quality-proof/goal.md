# Foil iOS Useful Dictation Quality Proof

## Original Request

Continue beyond plumbing and prove that iPhone dictation produces useful text.

## Outcome

Produce a privacy-safe physical or simulator-backed proof that a known spoken phrase becomes a useful transcript and can be inserted, while punctuation-only/no-speech results are rejected or guided into retry.

## Oracle

The board is true when a sterile known phrase yields a non-punctuation transcript close enough for the test oracle, the keyboard offers Insert latest for it, and weak/no-speech output does not masquerade as success.

## Constraints

- Do not commit API keys, private recordings, private transcripts, or raw WDA trees.
- Prefer deterministic sterile audio where possible; physical microphone proof is required before claiming real iPhone quality.
- Keep transcript-body evidence limited to known sterile phrases.

## Starter Command

`/goal Follow docs/goals/ios-useful-dictation-quality-proof/goal.md.`
