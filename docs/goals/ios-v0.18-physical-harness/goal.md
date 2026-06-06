# Foil iOS v0.18 Physical Harness

## Original Request

Plan the next several GoalBuddy prep boards and manage the iOS prototype through
them with as much autonomy as is safe.

## Outcome

Build a repo-native physical iPhone test harness that makes the proven WDA and
App Group flows repeatable without exposing private host-app content.

## Oracle

This board is complete only when a committed harness can:

- Check whether the preview iPhone and WDA endpoint are reachable.
- Start or print the exact WDA command needed for `iPhone-preview`.
- Create a current-app WDA session without relaunching sensitive apps.
- Stage a sterile fake transcript into `group.com.neonwatty.FoilIOS` at the
  correct `Library/foil-keyboard-snapshot.json` path.
- Read back only sanitized App Group state: phase, hasTranscript, and text hash.
- Collect sanitized WDA receipts through the existing evidence helper without
  committing raw XML, screenshots, contacts, thread names, or message bodies.
- Reset the App Group to idle/no transcript after proof.

## Non-Goals

- Do not automate inspection of private Messages threads or existing user data.
- Do not send messages.
- Do not require App Store Connect, Groq, or other credentials.
- Do not change keyboard product behavior unless the harness exposes a blocker
  that must be fixed in the same PR.

## Seed Plan

1. Scout the current scripts, runbook, device identifiers, and v0.15-v0.17
   receipts to identify the smallest useful harness interface.
2. Judge the first vertical slice and its privacy boundary.
3. Implement the harness, docs, and a fixture-based self-test.
4. Run one physical dry proof if the phone/WDA are available, otherwise record
   an exact external blocker and leave the fixture proof in place.
5. Audit the strongest failure mode: the harness accidentally leaking raw
   host-app text into committed files.

## Starter Command

`/goal Follow docs/goals/ios-v0.18-physical-harness/goal.md.`
