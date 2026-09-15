# Foil

**Talk to agents at the speed of thought.**

macOS dictation built for AI-first work - fast, direct prompts for agents and
polished text for humans. Run local models or connect to a transcription API.

[Website](https://foil.neonwatty.com/) ·
[Latest release](https://github.com/usefoil/foil/releases/latest) ·
[Changelog](CHANGELOG.md)

[![Foil](https://foil.neonwatty.com/assets/foil-social-card.png?v=20260914-ai-first)](https://foil.neonwatty.com/)

Foil is open source. Hold a hotkey, speak, and release. Foil transcribes your
audio, applies the right cleanup settings for the current app, and pastes the
result where you were typing.

## Features

- Hold-to-record, toggle mode, and customizable hotkeys
- Local whisper.cpp, Groq, OpenAI Whisper, and custom OpenAI-compatible providers
- App-specific Cleanup Groups for direct agent prompts or polished human writing
- Automatic paste with history, retry, and clipboard recovery
- Searchable local transcription history
- Local usage insights for words, sessions, time saved, and top apps

## Install

Foil supports macOS 14 or later on Apple Silicon and Intel Macs.

```sh
brew tap mean-weasel/foil https://github.com/mean-weasel/homebrew-foil
brew install --cask foil
```

You can also download the signed and notarized DMG from the
[latest GitHub release](https://github.com/usefoil/foil/releases/latest).

## Get started

1. Launch Foil from Applications. It stays in the menu bar.
2. First-run setup recommends **On this Mac**, which needs no API key. Existing provider choices are preserved.
3. For local transcription, follow the one-time whisper.cpp install/build/model instructions in setup, then **Start local model** and **Test connection**. The current local path requires Terminal, CMake, and Apple's command-line developer tools; a bundled installer is not yet included.
4. Prefer cloud transcription? Choose **Groq** or **OpenAI Whisper**. Setup links to the provider's key-management page and official setup guide, explains account requirements, and lets you **Save & Test** inline. Keys are stored in macOS Keychain.
5. Grant Microphone and Accessibility access when prompted.
6. Practice your shortcut and record a short phrase. Your practice transcript appears in Foil without being pasted or saved to History.
7. Try another dictation in a blank Notes or TextEdit document. Foil keeps your confirmation of external insertion separate from the successful practice transcript.
8. Choose **Get Started**, or **Finish setup later** to postpone setup without marking it complete. Reopen the walkthrough from Home -> **Setup and dictation practice**.

Cloud setup resources:

- [Groq API keys](https://console.groq.com/keys) and [official quickstart](https://console.groq.com/docs/quickstart)
- [OpenAI API keys](https://platform.openai.com/api-keys) and [official quickstart / billing guidance](https://developers.openai.com/api/docs/quickstart)

A successful setup connection check does not prove transcription or external
insertion. The practice dictation and insertion steps test those separately.

## Providers

| Provider | Where transcription runs | Credentials |
| --- | --- | --- |
| Local whisper.cpp | On your Mac through a local server | None |
| Groq Whisper | Groq | Groq API key |
| OpenAI Whisper | OpenAI | OpenAI API key |
| Custom OpenAI-compatible | Your configured endpoint | Optional |

Transcription and cleanup are configured separately. Cleanup Groups can route
transcript text through Groq, OpenAI, or a custom OpenAI-compatible chat
endpoint. Unassigned apps stay fast and direct with raw transcripts by default.

- **Groq** is a cloud option and requires a Groq API key. Audio is sent to Groq for
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

See the
[local whisper.cpp guide](docs/local-openai-compatible-transcription-e2e.md)
for setup details.

## Privacy

- API keys are stored in the macOS Keychain.
- History and usage insights stay on your Mac and can be limited or deleted.
- Turning history off stops new storage; use Clear History to delete previously
  stored records. The latest dictation stays in memory for Copy last result
  until Foil quits or history is cleared.
- Successful recordings are deleted after transcription. Audio from retryable
  failures may be retained locally until its history entry is deleted.
- Local diagnostics are redacted before writing and should not include API keys,
  transcript text, raw audio, or clipboard contents.
- Audio and cleanup text are sent only to the providers you configure.

## Paste Caveats

macOS paste automation depends on Accessibility permission and target-app
behavior. Foil distinguishes verified direct insertion, command-posted paste,
window-choreography paste, and clipboard fallback internally. A command being
posted does not prove every target app accepted it; use History or the clipboard
fallback when a target blocks paste automation.

Try background paste is off by default. It uses lower-level macOS routing when
available and should be treated as an experimental compatibility option, not as
the default reliability path.

## Development

You need Xcode with macOS 14 SDK support. Node.js and npm are used by the
release tooling.

```sh
npm ci
make setup-local-signing
make build
make test
```

For day-to-day development, install and launch the isolated development build:

```sh
make install-dev
make start-dev
```

The dev flavor installs `/Applications/Foil Dev.app` with bundle ID
`com.neonwatty.Foil.Dev`. It keeps separate macOS permissions, preferences,
Keychain entries, diagnostics, and transcription history from production.
Sparkle updates are disabled in the dev flavor so it will not replace itself
with a production release.

To repair or inspect the dev app's macOS permission rows, use:

```sh
make prepare-local-permissions-dev-qa
make prepare-local-permissions-dev-qa-check
```

## Troubleshooting

**Invalid API key:** Use **Add Key** or Settings -> Transcription ->
**Change API Key**. Foil validates the key before saving when the network is
available. If validation fails because the selected provider cannot be reached,
you can save the key anyway and run the setup check later.

**Local whisper.cpp not reachable:** Start `whisper-server` with the command
shown in Settings -> Transcription, then click **Test connection**. The local
provider expects `http://127.0.0.1:8080/v1` and the compatibility model
`whisper-1`.

**Paste command sent but no text appears:** The target app may block synthetic
paste events. Open History to copy or paste the transcript again. If Foil
reports clipboard fallback, the transcript is on the clipboard.

**Copy setup report:** Use **Copy Setup Report** from the menu bar app or
Settings -> Storage -> Support. The report is copied as Markdown with app
version, provider configuration, permission states, setup status, and recent
redacted diagnostics. It does not include API keys, transcript text, audio, or
clipboard contents.

## Requirements

- macOS 14+ (Sonoma)
- A configured local whisper.cpp model/server, or credentials for your selected cloud provider
- Accessibility permission (for global hotkey and paste automation)
- Microphone permission (for recording)

## License

[MIT](LICENSE)
