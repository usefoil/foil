# iOS Real Dictation Reliability v0.4

## Original Request

Continue the iOS keyboard/dictation work by hardening the next reliability slice, using GoalBuddy prep and then implementing it.

## Outcome

Foil iOS has a fresh TestFlight build and a repeatable physical iPhone-preview proof that the keyboard can record, transcribe, insert the latest transcript into Notes, and reset shared state across multiple consecutive cycles.

## Oracle

On the physical iPhone-preview device, TestFlight build 0.1.0 (6) must complete at least three consecutive live record -> Groq transcribe -> keyboard insert -> shared-state reset cycles in Notes, with screenshots/log snapshots proving:

- the installed app is build 6;
- each cycle used a newly recorded audio file rather than stale transcript text;
- the keyboard showed and inserted the latest transcript;
- shared app-group state returned to idle/Ready after insertion;
- failure or mismatch cases are called out instead of hidden.

## Constraints

- Do not print or commit App Store Connect private keys, Groq keys, JWTs, or device-private content.
- Do not revert unrelated user changes or untracked Xcode/user files.
- Keep implementation changes scoped to iOS build metadata and reliability-test support unless a blocking bug is found.
- Prefer simulator/build tests for compile-time proof and physical iPhone-preview checks for keyboard insertion proof.
- Preserve evidence under this goal directory.

## Likely Misfire

The board could upload a build and pass a single happy-path smoke while reusing stale transcript state, skipping the keyboard insertion path, or relying on an imprecise audio phrase that does not prove the real dictation loop. The final audit must explicitly try to disprove those failure modes.

## Starter Command

`/goal Follow docs/goals/ios-real-dictation-v0.4/goal.md.`
