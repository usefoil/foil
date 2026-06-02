# Acceptance Evidence

Foil changes should close with evidence that tries to disprove the claim being
made. Passing tests are useful, but they are not the claim by themselves. A good
receipt names the user-facing or operational claim, the realistic way it could
still be wrong, and the command, artifact, trace, screenshot, or inspection that
rules out that failure.

Use this guide to pick proof that matches the risk. Small docs or config edits
may only need one strong failure mode and a direct inspection. User-facing,
release, permission, paste, provider, or automation changes should list the top
realistic failure modes and evidence for each one.

## Evidence Receipt

Use this shape in PRs, goal receipts, release logs, and final handoffs:

```text
Claim:
Strongest realistic failure mode:
Evidence:
Residual risk / follow-up:
```

For larger or riskier changes, repeat the failure-mode and evidence rows for the
top realistic failure modes. Treat skipped checks as risk to explain, not as a
pass.

## Change Matrix

| Change type | Primary evidence | Strong failure modes to try to rule out |
| --- | --- | --- |
| Swift model, controller, service, or utility change | Focused `xcodebuild test ... -only-testing:FoilTests/<Suite>` plus `make test` when the touched code is shared. | The focused test passed but an adjacent caller broke; live Groq tests accidentally ran or were masked by stale env; warnings or compile-time issues were missed. |
| Build settings, signing, project, or release-script change | `make build-warnings-as-errors`; relevant script tests such as `scripts/test-build-notarized-qa-dmg.sh`; direct diff inspection of `Foil.xcodeproj/project.pbxproj` or release scripts. | Debug builds pass but warning-clean CI fails; signing or bundle identity changes unintentionally; release scripts accept a malformed artifact. |
| Settings, onboarding, history, or visible app UI change | Focused `FoilUITests` rows for the changed state; use `make test-ui-diagnostics` for broad or flaky UI-risk changes; include screenshots or `xcresult` paths when visual state matters. | The happy path renders but an alternate permission/provider/history state regresses; visible copy exists but controls are disabled or inaccessible; stale app state hides the issue. |
| Paste, Accessibility, Input Monitoring, queued paste, or cross-app routing change | `make test-cross-app`, `make test-queued-paste-compatibility`, `make prepare-local-permissions-qa-check`, and diagnostics from `~/Library/Application Support/Foil/Diagnostics/foil.log` when relevant. | The command-posted paste path reports success but target text did not change; Accessibility trust belongs to an old app identity; clipboard fallback works but target routing does not. |
| Provider, transcription, cleanup, API-key, or local OpenAI-compatible change | `make test-provider-qa`; focused provider unit tests; `RUN_LIVE_GROQ_TESTS=1 GROQ_API_KEY=... make test-live-groq` only when live Groq proof is required; `make test-local-transcription-e2e` for local server flows. | Deterministic tests pass while real API or local server behavior fails; transcript text or keys leak into logs; cleanup failure loses a successful raw transcript. |
| Microphone, recording, audio-device, or other-audio behavior change | Focused recorder/audio tests; `make test-microphone-live` when live capture proof is required; manual smoke notes for hardware-dependent behavior. | Automated state says ready while macOS permission or hardware state differs; Bluetooth input mode changes output behavior; diagnostics omit the active audio policy. |
| Release, notarization, Sparkle, DMG, or Homebrew change | `docs/release-process.md`; `docs/release-qa-log.md`; Notarized QA Build workflow; `spctl`, `codesign --verify --deep --strict`, `xcrun stapler validate`, checksum, and Homebrew cask smoke. | The app builds but is not notarized or stapled; cask SHA does not match the release DMG; Sparkle appcast points at the wrong asset; release helper uses stale version/build values. |
| Website or static asset change | Local file inspection plus the Pages workflow when published; browser screenshot for layout or screenshot asset changes. | The site builds but displays an old or missing asset; screenshot claims do not match current deterministic UI-test states; mobile layout hides important content. |
| Docs, runbook, goal, or agent-instruction change | `git diff --check`; direct inspection of every referenced path/command; inspect `AGENTS.md` when repo-level agent guidance changes. | The new guidance references commands or files that do not exist; agent instructions drift away from repo practice; wording adds process overhead without a concrete evidence path. |

## Recording Skips

If a check cannot run, record:

- The exact command or scenario that was skipped.
- Why the skip is acceptable for this change.
- The risk owner or follow-up that would close the gap.

Do not use `ALLOW_LOCAL_QA_SKIP=1` without recording the local condition that
made the skip necessary.

## Release And Goal Logs

Release evidence belongs in `docs/release-qa-log.md`. Larger multi-step product
work should keep its oracle and receipts in `docs/goals/<topic>/goal.md` and
the matching board state when GoalBuddy is in use. The evidence standard is the
same in both places: name the claim, try to disprove it, and preserve the proof.
