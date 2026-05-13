# GroqTalk v2: Distribution, Features & Polish

**Goal:** Make GroqTalk discoverable and installable by strangers — polished app icon, clean README, new user-facing features (language hint, history popover), and automated DMG + Homebrew distribution with code signing and notarization.

**Architecture:** Three independent sub-projects executed in order: Polish → Features → Distribution. Each can ship independently. Polish gives the app a public-ready identity. Features add the last user-facing capabilities before wider release. Distribution automates the packaging and install experience.

**Tech Stack:** SwiftUI, AVFAudio, Groq Whisper API, GitHub Actions, `create-dmg`, `notarytool`, Homebrew Cask, `logo-designer-skill` plugin

---

## Sub-project 1: Polish (README + App Icon)

### App Icon

Generate an app icon using the `logo-designer-skill` Claude Code plugin (`neonwatty/logo-designer-skill`).

**Requirements:**
- Format: Icon only (512x512 viewBox)
- Style direction: Minimal/geometric, consistent with the existing waveform menu bar icon
- Theme: Speech-to-text / voice / waveform motif
- Output: SVG concepts → iterations → final export to all standard PNG sizes
- The 1024x1024 PNG gets placed into `GroqTalk/Assets.xcassets/AppIcon.appiconset/` with the corresponding `Contents.json` updated

**Process:**
1. Invoke the logo-designer-skill
2. Provide context: macOS menu bar speech-to-text app, Groq-powered, waveform motif
3. Iterate through concepts until satisfied
4. Export PNGs and integrate into Xcode project

### README

Clean, concise README targeting developers and power users who want fast speech-to-text.

**Structure:**
1. **Header**: App name + one-liner: "macOS menu bar speech-to-text powered by Groq Whisper"
2. **Demo**: Placeholder for a GIF showing hold-to-record → transcribe → paste flow (user records manually)
3. **Install**:
   - Homebrew: `brew tap neonwatty/tap && brew install --cask groqtalk`
   - Manual: DMG download link from GitHub releases
4. **Setup**: Get a Groq API key → paste into app settings
5. **Features**: Bullet list — 3 audio formats (WAV/M4A/FLAC), hold-to-record hotkey (Right Option or Globe), transcription history with retry, language selection, auto-paste into active app
6. **License**: MIT (or whatever the project uses)

No contributing guide, FAQ, or configuration deep-dive. Keep it tight.

---

## Sub-project 2: Features

### Language Hint

Add an optional language parameter to improve Whisper transcription accuracy for non-English audio.

**Language enum:**

```swift
enum Language: String, CaseIterable, Codable {
    case auto = "auto"
    case en, es, fr, de, pt, it, ja, zh, ko, hi, ar, ru

    var displayName: String {
        switch self {
        case .auto: "Auto-detect"
        case .en:   "English"
        case .es:   "Spanish"
        case .fr:   "French"
        case .de:   "German"
        case .pt:   "Portuguese"
        case .it:   "Italian"
        case .ja:   "Japanese"
        case .zh:   "Chinese"
        case .ko:   "Korean"
        case .hi:   "Hindi"
        case .ar:   "Arabic"
        case .ru:   "Russian"
        }
    }
}
```

**Changes:**

- **`AppState`**: New `selectedLanguage: Language` property backed by UserDefaults, default `.auto`
- **`TranscriptionService.transcribe()`**: Accept optional `language: Language` parameter. When not `.auto`, add a `language` field to the multipart body with the ISO 639-1 code.
- **`TranscriptionService.buildMultipartBody()`**: Conditionally append the language part when language is not `.auto`.
- **`MenuBarView`**: Add a "Language" picker below the existing "Audio Format" picker, same Picker style.
- **`GroqTalkApp`**: Pass `appState.selectedLanguage` through to the `transcribe()` call.

**Behavior:** When set to "Auto-detect" (default, rawValue `"auto"`), no `language` parameter is sent to the API — Whisper auto-detects. The `"auto"` rawValue is only used for persistence; the multipart body conditionally omits the field when `language == .auto`. When a specific language is selected, its rawValue (e.g., `"en"`, `"ja"`) is sent as a hint that improves accuracy but doesn't force the language.

### History Popover

Replace the inline menu history items with a richer popover view, opened via a "Show History..." menu item.

**UI:**
- A "Show History..." button in the menu bar dropdown
- Opens a SwiftUI popover (`.popover` modifier) anchored to the menu bar
- Fixed size: ~350pt wide, ~400pt tall
- Dismisses on click outside

**Popover contents:**
- **Search field** at the top — filters records by text content
- **Scrollable list** of `TranscriptionRecord`s, each showing:
  - Preview text (truncated) or error message (styled red)
  - Relative timestamp ("just now", "2 min ago", etc.)
  - Copy button — copies full text to clipboard
  - Retry button on failed records with audio files (reuses existing `retryableRecord` / `resolveRetry` logic)
- **Empty state**: "No transcriptions yet" when history is empty

**Data layer:** No changes needed. The existing `TranscriptionHistory` class and `TranscriptionRecord` model already support everything the popover needs — `records` array, `previewText`, `relativeTimestamp`, `isFailure`, `retryableRecord`, `resolveRetry()`.

**Architecture:**
- New file: `HistoryPopoverView.swift` — the popover content view
- Modified: `MenuBarView.swift` — replace inline history items with "Show History..." button + popover state
- Modified: `GroqTalkApp.swift` — wire up retry action from the popover

---

## Sub-project 3: Distribution

### Code Signing & Notarization

Sign and notarize the app so macOS Gatekeeper accepts it without warnings.

**GitHub Actions Secrets required:**
- `DEVELOPER_ID_CERT_BASE64` — base64-encoded `.p12` Developer ID Application certificate
- `DEVELOPER_ID_CERT_PASSWORD` — password for the `.p12` file
- `APPLE_TEAM_ID` — Apple Developer Team ID
- `APPLE_ID` — Apple ID email for notarization
- `APPLE_ID_PASSWORD` — app-specific password for notarization (not the account password)

**Build steps:**
1. Import certificate into a temporary keychain in the GitHub Actions runner
2. `xcodebuild archive` with `CODE_SIGN_IDENTITY="Developer ID Application"` and hardened runtime
3. `xcodebuild -exportArchive` to produce a signed `.app`
4. Verify with `codesign --verify --deep --strict`

**Entitlements:** The existing `GroqTalk.entitlements` already has `com.apple.security.device.audio-input`. No additional entitlements needed — TextInserter uses CGEvent (not AppleScript), so no automation entitlement is required.

### DMG Build

Produce a styled DMG and attach it to the GitHub release.

**Tool:** `create-dmg` (installed via Homebrew in CI: `brew install create-dmg`)

**DMG contents:** GroqTalk.app + symbolic link to /Applications, with drag-to-install layout.

**Notarization of DMG:**
1. Build and sign the `.app` (above)
2. Create DMG with `create-dmg`
3. Submit DMG to Apple: `xcrun notarytool submit GroqTalk.dmg --apple-id ... --team-id ... --password ... --wait`
4. Staple the ticket: `xcrun stapler staple GroqTalk.dmg`

**Deploy workflow changes (`.github/workflows/deploy.yml`):**

The existing workflow runs semantic-release on push to main. Add a `build-dmg` job that runs after semantic-release, only when a new release was created:

```
semantic-release → (new tag created?) → build-dmg → upload DMG to release
```

**Job: `build-dmg`**
- Runs on `macos-15`
- Triggered only when semantic-release created a new release (check via `gh release view` for the tag)
- Steps: checkout tag → import cert → xcodebuild archive → export .app → create-dmg → notarize → staple → upload DMG as release asset via `gh release upload`

**Naming convention:** `GroqTalk-<version>-macos.dmg` (e.g., `GroqTalk-1.1.0-macos.dmg`)

### Homebrew Cask

Create a Homebrew tap so users can `brew install --cask groqtalk`.

**Tap repo:** `neonwatty/homebrew-tap` (new GitHub repo)

**Cask formula** (`Casks/groqtalk.rb`):

```ruby
cask "groqtalk" do
  version "<version>"
  sha256 "<sha256>"

  url "https://github.com/neonwatty/groqtalk/releases/download/v#{version}/GroqTalk-#{version}-macos.dmg"
  name "GroqTalk"
  desc "macOS menu bar speech-to-text powered by Groq Whisper"
  homepage "https://github.com/neonwatty/groqtalk"

  app "GroqTalk.app"

  zap trash: [
    "~/Library/Application Support/GroqTalk",
  ]
end
```

**Update strategy:** After each release, update the cask formula with the new version and SHA256. This can be done manually at first, or automated with a GitHub Action in the tap repo that listens for new releases on `neonwatty/groqtalk`.

**Install flow:**
```
brew tap neonwatty/tap
brew install --cask groqtalk
```

---

## Execution Order

1. **Polish** — app icon (logo-designer-skill) + README. No code dependencies. Ships as a PR.
2. **Features** — language hint + history popover. App code changes with tests. Ships as 1-2 PRs.
3. **Distribution** — code signing secrets → DMG pipeline → notarization → Homebrew tap. Ships as 1-2 PRs + new tap repo.

Each sub-project gets its own implementation plan via `writing-plans`.
