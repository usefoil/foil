# T002 Scout Receipt

Result: done

## Summary

Mapped feasible local demo-media workflows for Foil without capturing media yet.

Recommended first path: create a deterministic screenshot set from the real Foil app launched in `--ui-testing` mode with seeded states, then use those screenshots in public surfaces. This gives credible, current UI evidence without live Groq credentials, a local Whisper server, microphone access, or private desktop content.

## Recommended Screenshot Workflow

Use the existing UI-testing seed surface and real macOS window capture:

1. Build the app with `make build` or use the current Debug app bundle.
2. Launch Foil directly with safe seed flags, for example:
   - `--ui-testing --reset-defaults --seed-history`
   - `--ui-testing --reset-defaults --show-onboarding --seed-setup-ready`
   - `--ui-testing --reset-defaults --seed-history --seed-local-provider`
   - `--ui-testing --reset-defaults --seed-history --simulate-success-after-launch`
   - `--ui-testing --reset-defaults --seed-history --seed-floating-warning`
3. Open the target window or seeded state through existing UI-test command hooks where needed.
4. Identify the real window id and capture it with `/usr/sbin/screencapture -l <window-id> <path>.png`.
5. Stop Foil afterward with `pkill -x Foil` and verify no duplicate app process remains.

This repo has prior proof that the same approach works: `docs/goals/foil-ux-reorganization/notes/T008-visual-verification-worker.md` captured `ready-menu-host.png`, `setup-needed-menu-host.png`, `onboarding-setup.png`, and `settings-transcription.png` from real seeded app windows with `screencapture -l`.

Recommended initial public screenshot set:

- Ready menu/control center: seeded ready state with history and safe test copy.
- Settings Transcription with Local whisper.cpp selected: provider choice, local endpoint, and privacy posture.
- Onboarding local-provider path: shows local provider does not require an API key.
- Simulated success result: shows record-to-paste outcome using mock transcript copy.
- Optional floating status/fallback state: useful for workflow credibility, but less important than ready/provider/result.

## Video / GIF Options

Primary video option: after screenshots land, record a short manual demo against a clean desktop using macOS Screenshot/QuickTime or `screencapture -v` if available on the target macOS version. Use a disposable TextEdit document and a deliberately non-private phrase. This needs owner confirmation because desktop video can reveal surrounding apps, menu bar state, notifications, and local filenames.

Local-provider live demo option: run `make test-local-transcription-e2e` only after a local OpenAI-compatible Whisper server is intentionally started. This avoids Groq credentials, but it still requires owner setup and should use the existing bundled `Foil/e2e-test-audio.wav` or a newly approved non-private clip.

Groq live demo option: use only with explicit opt-in. Existing docs define `make test-provider-qa-live` / live E2E paths, but the goal constraints should avoid credentials unless the owner asks for a live Groq proof.

GIF option: capture screenshot frames or a short screen recording, then convert with `/opt/homebrew/bin/ffmpeg`. `gifski`, ImageMagick `convert`, and `magick` are not currently available on this machine.

## Tool Availability

Available locally:

- `/usr/sbin/screencapture`
- `/usr/bin/sips`
- `/opt/homebrew/bin/ffmpeg`
- `/usr/bin/xcrun`
- `/usr/bin/osascript`
- `/usr/bin/swift`
- `/usr/bin/xcodebuild`

Not found in PATH:

- `gifski`
- `convert`
- `magick`

## Verification Commands

Deterministic app/test verification:

```text
make build
make test-provider-qa
make test
```

Read-only/public-surface verification after assets are wired:

```text
rg -n "GroqTalk|Demo media has not been published yet|Foil-1.12.1-macos.dmg|GroqTalk-1.12.1-macos.dmg" README.md site docs/release-qa-log.md
find site README.md docs -iname '*.png' -o -iname '*.gif' -o -iname '*.mp4'
```

Capture cleanup verification:

```text
pgrep -x Foil || true
```

Live release consistency verification:

```text
gh release view v1.12.1 --repo mean-weasel/foil --json name,tagName,url,body,assets,isDraft,isPrerelease,publishedAt
```

## Owner Input / Stop Conditions

Need owner opt-in before:

- recording full-desktop video;
- capturing the current real desktop instead of isolated app windows;
- using a live Groq key;
- using a live microphone recording;
- showing personal transcripts, diagnostics, filenames, API keys, or other private state.

Stop if a capture surface exposes private content, if claims require behavior not verified by the current app, or if a Worker needs to edit source files outside the Judge-approved `allowed_files`.

## Recommendation for Judge

Pick a first Worker package that fixes public contradictions and lands a small deterministic screenshot set. The release asset-name contradiction found in T001 should be resolved or explicitly acknowledged before promoting demo media, because public credibility will still be undermined if README/site screenshots improve while release-facing copy conflicts with live assets.
