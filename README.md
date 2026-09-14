# Foil

Open-source dictation for macOS with local, hosted, and self-hosted
transcription.

[Website](https://foil.neonwatty.com/) ·
[Latest release](https://github.com/usefoil/foil/releases/latest) ·
[Changelog](CHANGELOG.md)

[![Foil](https://foil.neonwatty.com/assets/foil-social-card.png)](https://foil.neonwatty.com/)

Hold a hotkey, speak, and release. Foil transcribes your audio, applies the
right cleanup settings for the current app, and pastes the result where you
were typing.

## Features

- Hold-to-record, toggle mode, and customizable hotkeys
- Local whisper.cpp, Groq, OpenAI Whisper, and custom OpenAI-compatible providers
- App-specific Cleanup Groups with custom prompts and vocabulary
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
2. Choose a transcription provider.
3. Add an API key if the selected provider requires one.
4. Grant Microphone and Accessibility access when prompted.
5. Hold your chosen hotkey, speak, and release to transcribe.

## Providers

| Provider | Where transcription runs | Credentials |
| --- | --- | --- |
| Local whisper.cpp | On your Mac through a local server | None |
| Groq Whisper | Groq | Groq API key |
| OpenAI Whisper | OpenAI | OpenAI API key |
| Custom OpenAI-compatible | Your configured endpoint | Optional |

Transcription and cleanup are configured separately. Cleanup Groups can route
transcript text through Groq, OpenAI, or a custom OpenAI-compatible chat
endpoint. Unassigned apps use raw transcripts by default.

See the
[local whisper.cpp guide](docs/local-openai-compatible-transcription-e2e.md)
for setup details.

## Privacy

- API keys are stored in the macOS Keychain.
- History and usage insights stay on your Mac and can be limited or deleted.
- Successful recordings are deleted after transcription. Audio from retryable
  failures may be retained locally until its history entry is deleted.
- Audio and cleanup text are sent only to the providers you configure.

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

`Foil Dev` keeps its permissions, preferences, Keychain entries, diagnostics,
and history separate from the production app.

## License

[MIT](LICENSE)
