# T001 Public Surface Scout

## Current Public Surface Map

- `README.md`
  - Strong provider-neutral overview: "macOS menu bar speech-to-text with cloud and local transcription providers."
  - Biggest credibility gap is explicit line 5: "Demo media has not been published yet."
  - Install, provider, privacy, paste caveat, troubleshooting, and requirements sections are detailed and mostly consistent with current Foil positioning.
- `site/index.html` and live `https://mean-weasel.github.io/foil/`
  - Live page returns title `Foil - Push-to-talk speech to text for macOS`.
  - No `GroqTalk`/`groqtalk` references observed in live HTML.
  - No demo/screenshot/video surface observed; hero uses simulated product preview UI only.
  - Story covers core workflow, providers, Homebrew, GitHub release download, and macOS compatibility.
- GitHub release `v1.12.1`
  - Release title is now `Foil 1.12.1`.
  - Release body is empty.
  - Live assets are still named `GroqTalk-1.12.1-macos.dmg` and `GroqTalk-1.12.1-macos.dmg.sha256`, plus `appcast.xml`.
  - This conflicts with the Foil product story and with docs that claim `Foil-1.12.1-macos.dmg` assets.
- `docs/release-qa-log.md`
  - Lines 106, 111, and 112 claim v1.12.1 release assets use `Foil-1.12.1-macos.dmg` and `.sha256`.
  - Live GitHub release evidence contradicts those names; the live assets still use `GroqTalk-1.12.1-macos.dmg`.
- GitHub issue #143
  - Still open.
  - Notes that the existing latest release was still titled `GroqTalk 1.12.1`; title is fixed now, but the issue checklist remains broader than current state and does not mention stale asset filenames.

## Ranked Demo/Screenshot Gaps

1. **README demo gap**
   - Current README tells visitors no demo media exists.
   - This directly weakens trust for a public beta visitor.
   - Best evidence target: replace the line with links to a real screenshot set and/or short demo media.

2. **Release asset naming mismatch**
   - Live v1.12.1 assets still use `GroqTalk-*` names even though the release title says Foil.
   - This is a public-surface brand mismatch and can confuse install/download trust.
   - Best evidence target: either rename/upload Foil-named assets and update release notes, or record a conscious decision to supersede with the next Foil release instead of mutating v1.12.1 assets.

3. **Release QA log contradiction**
   - `docs/release-qa-log.md` claims Foil-named v1.12.1 assets that are not present live.
   - Best evidence target: update QA evidence to match current external state or defer correction to a release-prep Worker.

4. **Landing page lacks real media**
   - Site story is coherent, but the app preview is simulated; no real screenshots or demo media are linked.
   - Best evidence target: add a compact "See Foil in action" section or media strip once safe screenshots/GIF exist.

5. **Release body is empty**
   - The latest release page has no user-facing release notes.
   - Best evidence target: add concise notes with install, provider, privacy, and known-beta caveat links after deciding how to handle asset names.

## Media Capture Constraints And Privacy Risks

- Media must not show API keys, personal transcripts, diagnostics, private desktop content, or local paths.
- Real app capture may require Accessibility/Microphone consent, a clean desktop, a test target app, and either a live provider or a deterministic UI/testing mode.
- A short demo should use neutral test copy and a disposable target surface such as TextEdit or a local demo page.
- Local-provider capture may require whisper.cpp setup; Groq capture may require an API key and must not expose network/account details.
- Simulated product UI can help site aesthetics, but the goal oracle requires verified media or screenshots of the actual workflow.

## Candidate Worker Slices

1. **Public surface correction and release consistency slice**
   - Fix release-facing copy contradictions and document current v1.12.1 asset state.
   - Potential files: `docs/release-qa-log.md`, `README.md`, `site/index.html`, possibly GitHub release body/assets if approved by Judge.
   - Verification: `gh release view v1.12.1 --json name,assets,body`; `rg` stale terms; live page curl.

2. **Screenshot set slice**
   - Capture or produce verified screenshots of key real app surfaces: menu ready/listening/transcribing, provider settings, local setup helper/history if feasible.
   - Potential files: `site/assets/`, `README.md`, `site/index.html`.
   - Verification: image dimensions/files present; browser render; `rg` links; no secret-bearing text.

3. **Short demo media slice**
   - Create a 10-20 second workflow demo showing hold/speak/release/paste.
   - Potential files: `site/assets/`, `README.md`, `site/index.html`, release notes/body.
   - Verification: media exists, loads in browser, target transcript is neutral, and public surfaces link it.

4. **Landing-page media section slice**
   - Add a media-ready site section that can use screenshots now and video later.
   - Potential files: `site/index.html`, `site/styles.css`, `site/assets/`.
   - Verification: local and live browser render, mobile no overflow.
