# T005 What's New Decision

Decision: Implement a small bundled "What's New" tab in Settings.

Rationale:
- The user specifically suggested Settings as the possible surface.
- Settings already has a tab strip and an Updates section, so a native tab is discoverable without adding a new windowing concept.
- Bundled release-note data avoids a GitHub/API fetch when Settings opens and works offline.
- Release prep can update the bundled notes alongside `CHANGELOG.md`.
- The surface should be quiet and utility-shaped: recent release title/date plus concise bullets, not a marketing page.

Allowed implementation files:
- `Foil/SettingsView.swift`
- `Foil/ReleaseNotes.swift`
- `FoilTests/**`
- `FoilUITests/**`
- `Foil.xcodeproj/project.pbxproj` if a new source file must be added to build phases
- `CHANGELOG.md` only if release-note source text needs updating

Verification requirements:
- `make test-provider-qa` or a focused UI test proving the Settings tab exists and renders the current OpenAI note.
- `make build-warnings-as-errors` or equivalent warning-clean build after source changes.
- Direct inspection that the new surface does not fetch network data on Settings open.

Deferred:
- A first-launch What's New sheet or Sparkle-integrated release notes can come later if we want announcement behavior. For now, a Settings tab is the least risky useful slice.
