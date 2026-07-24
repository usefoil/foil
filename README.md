# Foil

macOS menu bar speech-to-text with cloud and local transcription providers.

## Product Preview

Foil is a small macOS menu bar app for dictation into the app you are already
using. Hold your hotkey, speak, release, and Foil transcribes with Groq, Local
whisper.cpp, or a custom OpenAI-compatible endpoint before pasting the result
back into your current text field.

![Foil ready control center](https://raw.githubusercontent.com/usefoil/foil-web/main/assets/screenshots/foil-ready-control-center.png)

The screenshot set in [`usefoil/foil-web`](https://github.com/usefoil/foil-web/tree/main/assets/screenshots)
uses real Foil app windows captured from deterministic UI-testing states. It
shows the menu control center, setup recovery, onboarding, and Transcription
settings without live credentials or private transcript content.

## Website

The static landing page lives in
[`usefoil/foil-web`](https://github.com/usefoil/foil-web) so marketing,
analytics, SEO, and web deployment work can move independently from macOS app
release work.

## Install

Homebrew is the primary supported install path; manual DMG download is
available if you prefer to install from GitHub Releases.

The `mean-weasel/homebrew-foil` tap is verified for the current release. It
installs the same signed and notarized DMG published on GitHub:

```sh
brew tap mean-weasel/foil https://github.com/mean-weasel/homebrew-foil
brew install --cask foil
```

If the tap is already configured, `brew install --cask mean-weasel/foil/foil`
also works. The cask checksum should match the release asset digest for the
published DMG.

**Manual DMG:** Download `Foil-VERSION-macos.dmg` from
[Releases](https://github.com/usefoil/foil/releases), verify it against
the GitHub release asset digest or matching `.sha256` checksum when one is
published, open it, and drag Foil into Applications.

## Setup

1. Launch Foil — it lives in your menu bar
2. Choose a transcription provider in first-run setup
3. For Groq, get a free API key from [console.groq.com](https://console.groq.com/), then click **Add API Key** and save/test your key
4. For OpenAI Whisper, create an API key at [platform.openai.com/api-keys](https://platform.openai.com/api-keys), then click **Add API Key** and save/test your key
5. For Local whisper.cpp or a custom OpenAI-compatible server, open Transcription Settings, configure the endpoint, and use **Test connection**
6. Open Accessibility settings from Foil and enable the current app
7. Open Microphone settings from Foil and allow microphone access
8. Use the setup test to confirm the app is ready

Foil is a menu bar app (`LSUIElement`), so it does not keep a normal Dock
window open. The built app includes macOS AppIcon assets for Finder,
Applications, and the branded drag-to-Applications DMG presentation; the menu
bar itself uses SF Symbol state icons.

## Providers

Foil supports four transcription provider paths:

- **Groq** is the default and requires a Groq API key. Audio is sent to Groq for
  transcription, and optional cleanup can use Groq chat models.
- **OpenAI Whisper** requires an OpenAI API key. Audio is sent to
  `https://api.openai.com/v1/audio/transcriptions` with the `whisper-1`
  transcription model.
- **Local whisper.cpp** uses a local OpenAI-compatible `whisper-server` at
  `http://127.0.0.1:8080/v1`. It does not need a Groq key. Settings includes
  copyable install, build, model download, and start commands.
- **Custom OpenAI-compatible** sends audio to the base URL and model you
  configure. API keys are optional when your server allows unauthenticated
  requests.

Cleanup modes can use Groq chat models or a Custom OpenAI-compatible chat
endpoint. OpenAI Whisper, Local whisper.cpp, and custom transcription remain raw
by default; Foil will not send non-Groq transcripts to Groq for cleanup unless
you explicitly select Groq as the cleanup provider. If you choose a custom
cleanup endpoint, transcript text is sent to that endpoint.

For local setup details and the opt-in local E2E check, see
[`docs/local-openai-compatible-transcription-e2e.md`](docs/local-openai-compatible-transcription-e2e.md).

## Local Development

Requirements:

- Xcode with macOS 14+ SDK support
- Node.js and npm for release tooling

```sh
npm ci
make setup-local-signing
make build
make install
make start
make test
```

`make test` is deterministic and skips live provider XTests even if your shell
contains stale provider test environment variables. To intentionally verify live
cloud paths, run `RUN_LIVE_GROQ_TESTS=1 GROQ_API_KEY=... make test-live-groq`
for Groq and `OPENAI_API_KEY=... make test-live-openai` for OpenAI Whisper.
Use current keys and do not paste keys into logs or issue comments.

By default, local builds use the `Foil Local Code Signing` identity when it
exists, falling back to ad-hoc signing otherwise. Stable local signing keeps the
app's Accessibility permission attached across rebuilds.
`make setup-local-signing` creates that identity once in a dedicated local
keychain and removes stale local copies from the login keychain.

### Production and Development Apps

Use tagged releases or Homebrew for the production app at `/Applications/Foil.app`
with bundle ID `com.neonwatty.Foil`. Use the local dev flavor for work from
`main` or feature branches:

```sh
make install-dev
make start-dev
```

The dev flavor installs `/Applications/Foil Dev.app` with bundle ID
`com.neonwatty.Foil.Dev`. It keeps separate macOS permissions, preferences,
Keychain entries, diagnostics, and transcription history from production. Sparkle
updates are disabled in the dev flavor so it will not replace itself with a
production release.

To repair or inspect the dev app's macOS permission rows, use:

```sh
make prepare-local-permissions-dev-qa
make prepare-local-permissions-dev-qa-check
```

The Codex Run action also uses the dev flavor by default. Set
`FOIL_RUN_FLAVOR=prod` only when you intentionally want that script to rebuild
and launch the production app identity.

### Local Permission State Repair

During development, macOS can keep Accessibility or Input Monitoring rows for an
older local build. When that happens, System Settings may show Foil enabled
while the current app still cannot use the permission. Run:

```sh
make prepare-local-permissions-qa
```

Then launch Foil, enable the newly opened Foil row in System Settings, and
restart the app. To inspect local permission state without changing it, run:

```sh
make prepare-local-permissions-qa-check
```

For a Developer ID install, pass your signing identity and team:

```sh
make install SIGN_IDENTITY="Developer ID Application" DEVELOPMENT_TEAM=YOURTEAMID
```

Release automation uses GitHub secrets for signing, notarization, and Homebrew
tap updates.

Apple signing and notarization:

- `DEVELOPER_ID_CERT_BASE64`
- `DEVELOPER_ID_CERT_PASSWORD`
- `APPLE_TEAM_ID`
- `APP_STORE_CONNECT_KEY_ID`
- `APP_STORE_CONNECT_ISSUER_ID`
- `APP_STORE_CONNECT_PRIVATE_KEY`

Homebrew cask publishing:

- `HOMEBREW_TAP_TOKEN` — a GitHub token with write access to
  `mean-weasel/homebrew-foil`. If this is missing or under-scoped, the release
  can still publish, but the cask update must be handled manually.

If the certificate files are in `~/Desktop/apple-developer-certificates`, run:

```sh
make setup-release-secrets
```

`make setup-release-secrets` uses `usefoil/foil` by default. Set `REPO`,
`CERT_DIR`, `P12_PATH`, `ISSUER_ID_PATH`, `PRIVATE_KEY_PATH`, `APPLE_TEAM_ID`,
or `APP_STORE_CONNECT_KEY_ID` to target a different repository or certificate
layout.

## Features

- **Hold-to-record** — hold Right Command, Right Option, or Globe/Fn to record, release to transcribe
- **Toggle mode** — press once to start, again to stop
- **Auto-paste** — by default, sends a paste command to the app active when transcription finishes
- **Return to starting app** — optional experimental paste routing that lets you dictate in one app, move on, and paste back where recording started
- **Try background paste** — optional experimental paste method for app-specific testing; disabled by default because it relies on lower-level macOS behavior and command-posted results are not fully verifiable
- **Clipboard safety** — by default, Foil restores the previous clipboard after posting paste; Settings can keep final text on the clipboard instead
- **3 audio formats** — M4A (smaller), WAV (lossless), FLAC (lossless, smaller)
- **Language selection** — hint Whisper for better accuracy in 12 languages
- **Cleanup modes** — optionally clean up or rewrite transcripts after Whisper; if cleanup fails after Whisper succeeds, Foil uses the raw transcript
- **Transcription history** — browse, search, edit, export, copy, paste, delete, and retry past transcriptions

Foil is microphone-first. It does not currently include a user-facing
audio-file import flow.

## Privacy

- API keys are stored in the macOS Keychain. Older plaintext API-key files are migrated on read when possible.
- Transcription history stays on this Mac in Application Support. Retention can be set to off, 100, 500, or 1000 records.
- Successful audio files are deleted after transcription.
- Failed audio may be retained locally in Application Support only for retryable transcription failures. Clearing history deletes retained retry files.
- Local diagnostics are redacted before writing and should not include API keys, transcript text, raw audio, or clipboard contents. Diagnostics are enabled by default for supportability; set `FOIL_DIAGNOSTICS=0` to disable local diagnostic logging.

## Paste Caveats

macOS paste automation depends on Accessibility permission and target-app
behavior. Foil distinguishes verified direct insertion, command-posted
paste, window-choreography paste, and clipboard fallback internally. A command
being posted does not prove every target app accepted it; use History or the
clipboard fallback when a target blocks paste automation.

Try background paste is off by default. It uses lower-level macOS routing when
available and should be treated as an experimental compatibility option, not as
the default reliability path.

## Troubleshooting

**Invalid API key:** Use **Add Key** or Settings → Transcription →
**Change API Key**. Foil validates the key before saving when the network is
available. If validation fails because the selected provider cannot be reached,
you can save the key anyway and run the setup check later.

**OpenAI Whisper unavailable:** Confirm the OpenAI API key is current, billing
and project limits allow transcription, and the network can reach
`https://api.openai.com/v1`.

**Local whisper.cpp not reachable:** Start `whisper-server` with the command
shown in Settings → Transcription, then click **Test connection**. The local
provider expects `http://127.0.0.1:8080/v1` and the compatibility model
`whisper-1`.

**Custom OpenAI-compatible server not reachable:** Check that the base URL uses
`http://` or `https://`, that the server exposes `/v1/audio/transcriptions`,
and that any required local network, firewall, or authentication setup is ready.

**Custom cleanup endpoint not reachable:** Confirm the chat server is running,
the base URL includes `/v1`, the model name matches the server, and any required
API key is saved in Cleanup settings.

**Microphone not available:** Open System Settings → Privacy & Security →
Microphone and allow Foil. Use **Run Check** after changing the permission.

**Accessibility or hotkey not working:** Open System Settings → Privacy &
Security → Accessibility and allow Foil. If Foil is already enabled but
still cannot record from the hotkey or paste text, remove the old Foil row,
reopen Foil, enable the new row, and restart the app.

**Paste command sent but no text appears:** The target app may block synthetic
paste events. Open History to copy or paste the transcript again. If Foil
reports clipboard fallback, the transcript is on the clipboard.

**Cleanup failed but raw transcript pasted:** Transcription succeeded, but the
cleanup endpoint failed or returned an unsupported response. Foil pasted the raw
transcript so your dictation is not lost.

**Recording too long:** Foil stops oversized recordings before upload to
avoid runaway memory use and Groq request-size failures. Try a shorter
recording.

**Copy setup report:** Use **Copy Setup Report** from the menu bar app or
Settings → Storage → Support. The report is copied as Markdown with app version,
provider configuration, permission states, setup status, and recent redacted
diagnostics. It does not include API keys, transcript text, audio, or clipboard
contents.

**Export diagnostics:** Use the app Help menu command **Export Diagnostics...**
or press Command-Option-D while Foil is active. Diagnostics are written to a
file you choose, with API keys, transcript text, audio, and clipboard contents
redacted.

**Reset local state:** Quit Foil, then remove the app data folder from
`~/Library/Application Support/Foil` if you want to clear history,
retained retry audio, and local diagnostics. API keys are stored separately in
Keychain; use Settings → Transcription → **Change API Key** to replace them.

**Updates or Homebrew:** Sparkle updates read the `appcast.xml` asset from the
`usefoil/foil` GitHub releases. Homebrew installs the verified cask from
the `mean-weasel/homebrew-foil` tap; if an install fails, confirm the cask
URL and checksum match the latest GitHub release DMG.

## Requirements

- macOS 14+ (Sonoma)
- Groq API key (free tier available)
- Accessibility permission (for global hotkey and paste automation)
- Microphone permission (for recording)

## License

[MIT](LICENSE)
