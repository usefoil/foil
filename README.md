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
