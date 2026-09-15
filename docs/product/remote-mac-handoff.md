# Remote Mac UX handoff — September 8, 2026

## Start here

Continue implementation and GUI testing on the destination Mac. The source Mac is in active use. GitHub is the durable coordination record; no running agent, desktop session, credentials, permissions, or local model installation is transferred by checking out this branch.

- Tracking issue: https://github.com/usefoil/foil/issues/396
- Checkpoint branch: `codex/ux-onboarding-improvements`, based on `78ff194`.
- [Complete original audit](2026-09-07-ux-audit.md): every recommendation and original evidence. Line references describe the audited revision, not the updated code.
- [Implementation progress and evidence](ux-implementation-progress.md): what is implemented, tested, and still unverified.
- [Acceptance evidence standard](../acceptance-evidence.md).
- [Seeded UI screenshots](../evidence/ux-onboarding/): portable evidence with synthetic text, not personal transcripts.

The original audit is a historical document. The user's subsequent instruction is authoritative: recommend local for new users because it requires no API key, preserve existing provider choices, and retain proper cloud instructions and official link-outs. Do not equate a selected local model with an installed/working model.

## Ordered work

1. [#397 Managed local installation and language-aware model setup](https://github.com/usefoil/foil/issues/397). Next milestone: a fresh user produces a real local transcript without Terminal or an API key.
2. [#398 Provider health and fresh-user acceptance](https://github.com/usefoil/foil/issues/398). Distinguish permission, credentials, model readiness, transcription, and insertion.
3. [#399 Focus-change insertion safeguards](https://github.com/usefoil/foil/issues/399). Verify actual target text and last-result recovery.
4. [#400 Cleanup/vocabulary, privacy defaults, and navigation](https://github.com/usefoil/foil/issues/400).
5. [#401 Appearance, accessibility, layout, and observed usability](https://github.com/usefoil/foil/issues/401).

Use the checkpoint PR for reviewing the existing tranche. Continue on a separate branch from this checkpoint, with a focused PR per stage. If the checkpoint is not merged, make the next PR's base the checkpoint branch; retarget after merge. Do not close the rollout issue just because the first PR merges.

## Destination setup

In a new checkout (choose an unused destination directory):

```sh
git clone git@github.com:usefoil/foil.git foil-ux
cd foil-ux
git fetch origin
git switch --track origin/codex/ux-onboarding-improvements
git status --short
git rev-parse HEAD
```

For an existing checkout, inspect `git status` first and preserve local work; do not reset it. Compare the fetched SHA with the checkpoint PR's head. Open this checkout in Codex on the destination Mac, read `AGENTS.md`, and start the next stage there.

Check prerequisites before tests:

```sh
xcode-select -p
xcodebuild -version
xcodebuild -list
security find-identity -v -p codesigning
```

Use a logged-in desktop session for XCUITest. Verify signing, test-runner permissions, microphone and Accessibility on this Mac; they are not inherited from the source machine. The prior run used `Developer ID Application: Mean Weasel LLC (B3A6AN2HA4)` with manual signing. Do not assume that identity exists here or silently substitute an identity and treat permission results as equivalent. Follow the repository's signing and acceptance guidance using credentials already available on the destination.

Do not copy Keychain contents, API keys, personal History, production preferences, or source-machine signing secrets into GitHub. Cloud/live-audio tests require destination-local configuration. Use fresh test state and synthetic phrases/documents for acceptance. Keep production installation and release work outside this handoff.

## Baseline verification

Run these on the destination Mac, not the source Mac. Save full logs and result bundles outside tracked source. This reproduces the deterministic unit baseline; add locally valid signing arguments if necessary:

```sh
RUN_LIVE_GROQ_TESTS=0 RUN_LIVE_MICROPHONE_TESTS=0 xcodebuild test \
  -scheme Foil -destination 'platform=macOS' \
  -parallel-testing-enabled NO \
  -only-testing:FoilTests -skip-testing:FoilTests/LiveGroqIntegrationTests \
  -resultBundlePath /tmp/foil-handoff-unit-tests.xcresult

xcodebuild build -scheme FoilDev -destination 'platform=macOS' \
  OTHER_SWIFT_FLAGS='-warnings-as-errors'
```

Use a new result-bundle path for each rerun. The source checkpoint receipt reports 706 XCTest unit tests and 9 Swift Testing tests, plus focused UI scenarios. These are historical counts; verify current results independently.

Focused UI coverage to reproduce includes Home/sidebar, General preferences, cleanup disclosure, local onboarding without API keys, inline cloud links, microphone permission transitions, transcript completion gating, completed onboarding keeping the menu app running, compact active indicators, and clipboard recovery warnings. Select the corresponding methods in `FoilUITests/FoilUITests.swift`, or run `make test-ui-diagnostics` for broad coverage after reviewing its desktop effects.

Additional acceptance commands exist in the Makefile: `make test-provider-qa`, `make test-local-transcription-e2e`, `make test-microphone-live`, `make test-cross-app`, `make test-queued-paste-compatibility`, and `make prepare-local-permissions-qa-check`. Read the recipes/scripts and configure the intended app identity before execution; some scenarios drive the desktop or depend on installed apps/models. Do not count skipped live checks as passes.

## What has and has not been transferred

Code, tests, the complete audit, progress receipts, and three seeded screenshots are in Git. Source-machine `/tmp/foil-ux-*.xcresult`, logs, and the original probe executable are not committed or remotely available. Their paths in the audit/progress document identify historical evidence only. Reproduce relevant tests on the destination and attach sanitized evidence or durable artifact links to each PR.

The checkpoint implements history preference persistence, explicit deletion, memory recovery, truthful delivery feedback, Home actions, coherent indicators, local-first guided onboarding, cloud key testing/link-outs, and practice gating. Local runtime installation still requires commands. Provider health, focus-safe routing, cleanup/vocabulary redesign, privacy default changes, appearance/accessibility, and live fresh-user acceptance remain unfinished. No release certification is implied.

Known testing lessons: an early default-migration test exposed initialization writing provider defaults before first-run detection; that regression was fixed. Two Home UI tests exposed child accessibility identifiers hidden by the panel container; containment fixed them. A test run stalled at Keychain; it was stopped without granting access and rerun using stable signing. Preserve these regression checks.

## Prompt for the destination Codex task

> Continue Foil's UX rollout tracked in GitHub issue #396. Read AGENTS.md, docs/product/remote-mac-handoff.md, the complete UX audit, and the implementation progress log. Work on this destination Mac; do not drive the original Mac's desktop. Preserve the checkpoint and existing user changes. Begin issue #397 with inspection of local runtime/model management and packaging constraints, record the approach, then implement a reviewable no-Terminal local setup flow with language-aware recommendations and recoverable verified downloads. Preserve existing providers and official cloud setup guidance. Test the strongest failure modes and distinguish deterministic fixtures from live capture/insertion proof. Update the progress log and PR with evidence and remaining risks. Continue stage by stage; do not release or install into production.
