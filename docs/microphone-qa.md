# Microphone QA

Regular CI does not require microphone permission, microphone hardware, Groq credentials, or macOS TCC prompts.

Run deterministic onboarding and setup coverage:

```bash
make test-ui
```

Run the opt-in live microphone smoke locally:

```bash
RUN_LIVE_MICROPHONE_TESTS=1 make test-microphone-live
```

Run the opt-in installed-app live microphone smoke against Mac mini 2:

```bash
RUN_INSTALLED_LIVE_MICROPHONE_TESTS=1 \
HOST=mm2 \
APP_PATH=/Applications/Foil.app \
scripts/run-installed-live-microphone-qa.sh
```

To run the same installed-app smoke from GitHub Actions, manually dispatch the
`Installed App Live Microphone QA` workflow. Use the default
`host=Jeremys-Mac-mini-2.local` and `ssh_user=jeremywatt`, set `app_path` to
the installed app under test, and provide the expected version/build. The
workflow collects the remote evidence directory into an
`installed-live-microphone-qa` artifact. It still requires an active desktop
login on the target Mac; if mm2 is at the login window after reboot,
LaunchServices cannot open the installed app.

This installed-app smoke connects over SSH, verifies the installed Foil bundle
identity, Developer ID signature, and Gatekeeper notarization state, then
launches the app with LaunchServices `open --env`. It defaults to the
`system-default` input route because the Mac mini 2 QA host uses a USB
microphone. The script fails unless the receipt reports `status=pass`,
authorized microphone permission, matching input route, Apple voice playback
when enabled, nonzero captured bytes, and a nonzero live or file audio level.
Evidence is written on the remote host under
`/tmp/foil-installed-live-microphone-qa-<timestamp>/` by default.

The live smoke launches a debug-only app hook that starts the real recorder,
uses the system default input route by default, plays Apple-generated speech
with `/usr/bin/say`, captures about eight seconds of audio, writes
`/tmp/foil-live-microphone-result.txt`, and verifies the result from XCUITest.
It records the app path, signing identity, microphone permission status,
start/stop state, selected input UID/name/transport, prepared device ID,
available input devices, Apple speech status, level samples, peak level, elapsed
time, captured byte count, and either a pass or a clear local prerequisite
failure. It also attaches a UI screenshot to the XCUITest result and writes a
recording-state PNG plus a final-state PNG under
`/tmp/foil-live-microphone-screenshots/` when the runner can write there. If
macOS denies that path, the test writes the screenshots under the XCTest runner
container temp directory and the script reports that directory in the
`screenshots=` line. On exit, the script also assembles
`/tmp/foil-live-microphone-artifacts/` by default with a manifest, receipt,
screenshots, direct-fallback log when present, and a captured WAV when the run
fails due to silence or capture validation. It does not require network or Groq
API availability.

To produce a GitHub-hosted artifact instead of local-only screenshot paths, run
the `Live Microphone QA` workflow manually from GitHub Actions. It runs on the
self-hosted trusted macOS E2E runner, executes the same live smoke, writes the
receipt into the step summary, and uploads a `live-microphone-qa` artifact with
the same manifest, receipt, and screenshot bundle. The workflow defaults to
`system-default` because the Mac mini runner does not have a built-in
microphone; use `built-in` only when dispatching the workflow to hardware with
a built-in microphone, such as a MacBook.

When the Apple-speech path fails, the receipt preserves the captured WAV path in
`captured_audio_path` so the recording can be inspected instead of relying only
on the pass/fail line.

If local XCUITest cannot initialize automation mode, the script falls back to
launching the built debug app's live-smoke hook directly. The fallback still
writes the same result receipt and attempts a screenshot under
`/tmp/foil-live-microphone-screenshots/`. When XCUITest reached the app before
falling back, `screenshots=` may point at the XCUITest runner container copy
instead.

Useful overrides:

```bash
RUN_LIVE_MICROPHONE_TESTS=1 \
LIVE_MICROPHONE_INPUT_ROUTE=built-in \
LIVE_MICROPHONE_APPLE_VOICE_TEXT="Foil microphone test phrase." \
LIVE_MICROPHONE_DURATION_SECONDS=3 \
LIVE_MICROPHONE_ARTIFACT_DIR=/tmp/foil-live-microphone-artifacts \
make test-microphone-live
```

To run the older ambient-input smoke without Apple speech or a forced built-in
route:

```bash
RUN_LIVE_MICROPHONE_TESTS=1 \
LIVE_MICROPHONE_INPUT_ROUTE=system-default \
LIVE_MICROPHONE_APPLE_VOICE_TEXT= \
make test-microphone-live
```

For the default automated path, the result file should include:

- `status=pass`
- `input_route_request=system-default`
- `apple_voice_playback=enabled`
- `apple_voice_process_started=true`
- `level_peak` or `file_level_peak` at or above the XCUITest threshold

For a MacBook built-in microphone proof, dispatch the workflow or run the local
smoke with `LIVE_MICROPHONE_INPUT_ROUTE=built-in`; in that case the result
should also include `selected_input_transport=Built-in`.

The live smoke intentionally fails if the WAV file is non-empty but silent.
`bytes` alone is not treated as proof of microphone capture.

The XCUITest also checks the live recording UX while the real recorder is active:
the session title changes to `Recording`, the Start button is disabled, Stop and
Cancel are enabled, and the floating live feedback HUD is visible before the
audio receipt is allowed to pass.

If macOS permission state is stale:

```bash
tccutil reset Microphone com.neonwatty.Foil
RUN_LIVE_MICROPHONE_TESTS=1 make test-microphone-live
```

When prompted, allow microphone access for the Foil test app. If no prompt appears, open System Settings > Privacy & Security > Microphone and verify Foil is allowed.
