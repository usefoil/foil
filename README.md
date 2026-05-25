# GroqTalk

macOS menu bar speech-to-text powered by [Groq Whisper](https://console.groq.com/).

Demo media has not been published yet.

## Install

GroqTalk is still in beta. The supported beta install paths are the signed,
notarized DMG and the verified Homebrew cask.

**Manual DMG:** Download `GroqTalk-VERSION-macos.dmg` from
[Releases](https://github.com/mean-weasel/groqtalk/releases), verify it against
the GitHub release asset digest or matching `.sha256` checksum when one is
published, open it, and drag GroqTalk into Applications.

### Homebrew

The `mean-weasel/homebrew-groqtalk` tap is verified for the current public beta
release. It installs the same signed and notarized DMG published on GitHub:

```sh
brew tap mean-weasel/groqtalk https://github.com/mean-weasel/homebrew-groqtalk
brew install --cask groqtalk
```

If the tap is already configured, `brew install --cask mean-weasel/groqtalk/groqtalk`
also works. The cask checksum should match the release asset digest for the
published DMG.

## Setup

1. Launch GroqTalk — it lives in your menu bar
2. Choose a transcription provider in first-run setup
3. For Groq, get a free API key from [console.groq.com](https://console.groq.com/), then click **Add API Key** and save/test your key
4. For Local whisper.cpp or a custom OpenAI-compatible server, open Transcription Settings, configure the endpoint, and use **Test connection**
5. Open Accessibility settings from GroqTalk and enable the current GroqTalk app
6. Open Microphone settings from GroqTalk and allow microphone access
7. Use the setup test to confirm the app is ready

GroqTalk is a menu bar app (`LSUIElement`), so it does not keep a normal Dock
window open. The built app includes macOS AppIcon assets for Finder,
Applications, and DMG presentation; the menu bar itself uses SF Symbol state
icons.

## Providers

GroqTalk supports three transcription provider paths:

- **Groq** is the default and requires a Groq API key. Audio is sent to Groq for
  transcription, and optional cleanup can use Groq chat models.
- **Local whisper.cpp** uses a local OpenAI-compatible `whisper-server` at
  `http://127.0.0.1:8080/v1`. It does not need a Groq key. Settings includes
  copyable install, build, model download, and start commands.
- **Custom OpenAI-compatible** sends audio to the base URL and model you
  configure. API keys are optional when your server allows unauthenticated
  requests.

Cleanup modes currently require Groq-compatible chat completions. Local and
custom transcription providers use raw transcripts until a compatible cleanup
provider is added.

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

`make test` is deterministic and skips live Groq API XTests even if your shell
contains stale Groq test environment variables. To intentionally verify the real
Groq API path, run `RUN_LIVE_GROQ_TESTS=1 GROQ_API_KEY=... make test-live-groq`.
Use a current key and do not paste the key into logs or issue comments.

By default, local builds use the `GroqTalk Local Code Signing` identity when it
exists, falling back to ad-hoc signing otherwise. Stable local signing keeps the
app's Accessibility permission attached across rebuilds. `make setup-local-signing`
creates that identity once in a dedicated local keychain and removes stale
GroqTalk-local copies from the login keychain.

### Local Permission State Repair

During development, macOS can keep Accessibility or Input Monitoring rows for an
older local build. When that happens, System Settings may show GroqTalk enabled
while the current app still cannot use the permission. Run:

```sh
make prepare-local-permissions-qa
```

Then launch GroqTalk, enable the newly opened GroqTalk row in System Settings,
and restart the app. To inspect local permission state without changing it, run:

```sh
make prepare-local-permissions-qa-check
```

For a Developer ID install, pass your signing identity and team:

```sh
make install SIGN_IDENTITY="Developer ID Application" DEVELOPMENT_TEAM=YOURTEAMID
```

Release DMG notarization uses App Store Connect API key secrets:

- `DEVELOPER_ID_CERT_BASE64`
- `DEVELOPER_ID_CERT_PASSWORD`
- `APPLE_TEAM_ID`
- `APP_STORE_CONNECT_KEY_ID`
- `APP_STORE_CONNECT_ISSUER_ID`
- `APP_STORE_CONNECT_PRIVATE_KEY`

If the certificate files are in `~/Desktop/apple-developer-certificates`, run:

```sh
make setup-release-secrets
```

`make setup-release-secrets` uses `mean-weasel/groqtalk` by default. Set `REPO`,
`CERT_DIR`, `P12_PATH`, `ISSUER_ID_PATH`, `PRIVATE_KEY_PATH`, `APPLE_TEAM_ID`,
or `APP_STORE_CONNECT_KEY_ID` to target a different repository or certificate
layout.

## Features

- **Hold-to-record** — hold Right Command, Right Option, or Globe/Fn to record, release to transcribe
- **Toggle mode** — press once to start, again to stop
- **Auto-paste** — by default, sends a paste command to the app active when transcription finishes
- **Return to starting app** — optional experimental paste routing that lets you dictate in one app, move on, and paste back where recording started
- **Try background paste** — optional experimental paste method for app-specific testing; disabled by default because it relies on lower-level macOS behavior and command-posted results are not fully verifiable
- **Clipboard safety** — by default, GroqTalk restores the previous clipboard after posting paste; Settings can keep final text on the clipboard instead
- **3 audio formats** — M4A (smaller), WAV (lossless), FLAC (lossless, smaller)
- **Language selection** — hint Whisper for better accuracy in 12 languages
- **Cleanup modes** — optionally clean up or rewrite transcripts after Whisper; if cleanup fails after Whisper succeeds, GroqTalk uses the raw transcript
- **Transcription history** — browse, search, edit, export, copy, paste, delete, and retry past transcriptions

GroqTalk's open beta is microphone-first. It does not currently include a
user-facing audio-file import flow.

## Privacy

- API keys are stored in the macOS Keychain. Older plaintext API-key files are migrated on read when possible.
- Transcription history stays on this Mac in Application Support. Retention can be set to off, 100, 500, or 1000 records.
- Successful audio files are deleted after transcription.
- Failed audio may be retained locally in Application Support only for retryable transcription failures. Clearing history deletes retained retry files.
- Local diagnostics are redacted before writing and should not include API keys, transcript text, raw audio, or clipboard contents. Diagnostics are enabled by default for supportability; set `GROQTALK_DIAGNOSTICS=0` to disable local diagnostic logging.

## Paste Caveats

macOS paste automation depends on Accessibility permission and target-app
behavior. GroqTalk distinguishes verified direct insertion, command-posted
paste, window-choreography paste, and clipboard fallback internally. A command
being posted does not prove every target app accepted it; use History or the
clipboard fallback when a target blocks paste automation.

Try background paste is off by default. It uses lower-level macOS routing when
available and should be treated as an experimental compatibility option, not as
the default reliability path.

## Troubleshooting

**Invalid API key:** Use **Add Key** or Settings → Transcription →
**Change API Key**. GroqTalk validates the key before saving when the network is
available. If validation fails because Groq cannot be reached, you can save the
key anyway and run the setup check later.

**Local whisper.cpp not reachable:** Start `whisper-server` with the command
shown in Settings → Transcription, then click **Test connection**. The local
provider expects `http://127.0.0.1:8080/v1` and the compatibility model
`whisper-1`.

**Custom OpenAI-compatible server not reachable:** Check that the base URL uses
`http://` or `https://`, that the server exposes `/v1/audio/transcriptions`,
and that any required local network, firewall, or authentication setup is ready.

**Microphone not available:** Open System Settings → Privacy & Security →
Microphone and allow GroqTalk. Use **Run Check** after changing the permission.

**Accessibility or hotkey not working:** Open System Settings → Privacy &
Security → Accessibility and allow GroqTalk. If GroqTalk is already enabled but
still cannot record from the hotkey or paste text, remove the old GroqTalk row,
reopen GroqTalk, enable the new row, and restart the app.

**Paste command sent but no text appears:** The target app may block synthetic
paste events. Open History to copy or paste the transcript again. If GroqTalk
reports clipboard fallback, the transcript is on the clipboard.

**Cleanup failed:** Whisper transcription succeeded, but the cleanup model did
not return usable text. GroqTalk uses the raw transcript and keeps going.

**Recording too long:** GroqTalk stops oversized recordings before upload to
avoid runaway memory use and Groq request-size failures. Try a shorter
recording.

**Copy setup report:** Use **Copy Setup Report** from the menu bar app or
Settings → Storage → Support. The report is copied as Markdown with app version,
provider configuration, permission states, setup status, and recent redacted
diagnostics. It does not include API keys, transcript text, audio, or clipboard
contents.

**Export diagnostics:** Use the app Help menu command **Export Diagnostics...**
or press Command-Option-D while GroqTalk is active. Diagnostics are written to a
file you choose, with API keys, transcript text, audio, and clipboard contents
redacted.

**Reset local state:** Quit GroqTalk, then remove the GroqTalk app data folder
from `~/Library/Application Support/GroqTalk` if you want to clear history,
retained retry audio, and local diagnostics. API keys are stored separately in
Keychain; use Settings → Transcription → **Change API Key** to replace them.

**Updates or Homebrew:** Sparkle updates read the `appcast.xml` asset from the
`mean-weasel/groqtalk` GitHub releases. Homebrew installs the verified cask from
the `mean-weasel/homebrew-groqtalk` tap; if an install fails, confirm the cask
URL and checksum match the latest GitHub release DMG.

## Requirements

- macOS 14+ (Sonoma)
- Groq API key (free tier available)
- Accessibility permission (for global hotkey and paste automation)
- Microphone permission (for recording)

## License

MIT
