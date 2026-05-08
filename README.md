# GroqTalk

macOS menu bar speech-to-text powered by [Groq Whisper](https://console.groq.com/).

<!-- TODO: Add demo GIF showing hold-to-record → transcribe → paste -->

## Install

**Homebrew:**

```
brew tap neonwatty/tap
brew install --cask groqtalk
```

**Manual:** Download the latest `.dmg` from [Releases](https://github.com/neonwatty/groqtalk/releases).

## Setup

1. Get a free API key from [console.groq.com](https://console.groq.com/)
2. Launch GroqTalk — it lives in your menu bar
3. Click the waveform icon → **Change API Key...** → paste your key

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

By default, local builds use the `GroqTalk Local Code Signing` identity when it
exists, falling back to ad-hoc signing otherwise. Stable local signing keeps the
app's Accessibility permission attached across rebuilds. `make setup-local-signing`
creates that identity once in a dedicated local keychain and removes stale
GroqTalk-local copies from the login keychain.

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

## Features

- **Hold-to-record** — hold Right Command, Right Option, or Globe/Fn to record, release to transcribe
- **Auto-paste** — transcribed text is pasted into your active app automatically
- **3 audio formats** — M4A (smaller), WAV (lossless), FLAC (lossless, smaller)
- **Language selection** — hint Whisper for better accuracy in 12 languages
- **Transcription history** — browse, search, copy, and retry past transcriptions
- **Toggle mode** — press once to start, again to stop (alternative to hold-to-record)

## Requirements

- macOS 14+ (Sonoma)
- Groq API key (free tier available)
- Accessibility permission (for global hotkey)
- Microphone permission

## License

MIT
