# Polish Implementation Plan (App Icon + README)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give GroqTalk a proper app icon and README so the repo and app are presentable for public discovery.

**Architecture:** The app icon is generated using the `logo-designer-skill` plugin, then exported PNGs are placed into the Xcode asset catalog. The README is a concise markdown file with install instructions, a demo placeholder, and feature highlights.

**Tech Stack:** `logo-designer-skill` plugin, Xcode asset catalog, Markdown

---

## File Structure

| File | Action | Responsibility |
|------|--------|---------------|
| `GroqTalk/Assets.xcassets/AppIcon.appiconset/Contents.json` | Modify | Reference the generated icon PNGs |
| `GroqTalk/Assets.xcassets/AppIcon.appiconset/*.png` | Create | Icon images at required sizes |
| `README.md` | Create | Project README |

---

### Task 1: Generate App Icon

**Files:**
- Modify: `GroqTalk/Assets.xcassets/AppIcon.appiconset/Contents.json`
- Create: `GroqTalk/Assets.xcassets/AppIcon.appiconset/icon-*.png`

- [ ] **Step 1: Install logo-designer-skill if not already installed**

```bash
claude plugin add neonwatty/logo-designer-skill
```

- [ ] **Step 2: Invoke the logo-designer-skill**

Start a conversation with Claude Code and say:

> "Create a logo for GroqTalk — a macOS menu bar speech-to-text app powered by Groq Whisper. Icon only (512x512). Minimal/geometric style. The app uses a waveform icon in the menu bar, so a waveform motif would be consistent. Surprise me on colors."

Follow the skill's interview → concepts → iterations → export flow.

- [ ] **Step 3: Copy the exported 1024x1024 PNG into the asset catalog**

```bash
cp logos/export/logo-1024.png GroqTalk/Assets.xcassets/AppIcon.appiconset/AppIcon.png
```

- [ ] **Step 4: Update Contents.json to reference the icon**

Replace `GroqTalk/Assets.xcassets/AppIcon.appiconset/Contents.json` with:

```json
{
  "images" : [
    {
      "filename" : "AppIcon.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "1024x1024"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
```

Note: Modern Xcode (14+) generates all required sizes from a single 1024x1024 source image.

- [ ] **Step 5: Build and verify the icon appears**

```bash
xcodebuild build -scheme GroqTalk -destination 'platform=macOS' 2>&1 | tail -3
```

Expected: BUILD SUCCEEDED. The app should show the new icon in Finder and the Dock (when launched).

- [ ] **Step 6: Commit**

```bash
git add GroqTalk/Assets.xcassets/AppIcon.appiconset/
git commit -m "feat: add app icon"
```

---

### Task 2: Create README

**Files:**
- Create: `README.md`

- [ ] **Step 1: Write README.md**

Create `README.md` in the project root:

```markdown
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
```

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: add README with install instructions and feature overview"
```
