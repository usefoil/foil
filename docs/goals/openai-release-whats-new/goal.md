# OpenAI Release, Installed QA, and What's New

## Original Request
Follow the release-quality path after merging OpenAI Whisper support: determine whether an updated notarized release exists, install the updated version locally for testing, and plan or implement a release-notes / What's New surface.

## Interpreted Outcome
A notarized QA build containing the OpenAI Whisper changes is produced from `main`, installed on this Mac, verified as a Developer ID / notarized app, and smoke-tested with OpenAI Whisper. The release-notes surface has a clear product decision and either a verified implementation or an explicit follow-up. If the QA build is clean, the next public-release step is prepared without publishing unexpectedly.

## Goal Oracle
The tranche is complete only when current evidence proves all of these:
- A Notarized QA Build has succeeded for `main` at or after merge commit `017dc25f704940eb495998d4c3048f197dfcf664`.
- The notarized QA artifact has been downloaded and installed locally.
- The installed app's bundle id, version/build, signature, notarization/Gatekeeper status, and launch path are verified.
- Installed-app OpenAI Whisper smoke testing succeeds without printing or committing secrets.
- The What's New / release-notes surface is decided: implemented and tested, or explicitly deferred with a tracked follow-up.
- Any public release prep is explicitly approved and verified before tagging or publishing.

## Constraints
- Do not print, commit, or upload `.env.local`, `OPENAI_API_KEY`, or any provider key.
- Do not reset Accessibility, Input Monitoring, Microphone, or other TCC permissions on the daily-driver account without explicit approval.
- Treat API-spend workflows as merge-queue/manual/scheduled only unless the user explicitly changes that policy.
- Do not create public tags, GitHub Releases, Homebrew updates, or production announcements without explicit version/build approval.
- Leave unrelated local files, including the marketing landing-page plan, untouched unless the user explicitly scopes them in.
- Use `docs/acceptance-evidence.md` and AGENTS.md burden-of-proof requirements before claiming completion.

## Likely Misfire
Stopping after a successful GitHub workflow or local debug build while never installing/verifying the notarized artifact, or implementing a large release-notes UI before deciding whether it belongs in Settings, About/Help, or a deferred follow-up.

## Current Tranche
1. Recreate or validate this GoalBuddy board.
2. Trigger/inspect notarized QA for the OpenAI merge.
3. Install and verify the notarized QA app locally.
4. Run installed-app OpenAI Whisper smoke testing.
5. Decide and, if approved, implement a small What's New/release-notes surface.
6. Prepare public release follow-up only after QA proof and explicit approval.
