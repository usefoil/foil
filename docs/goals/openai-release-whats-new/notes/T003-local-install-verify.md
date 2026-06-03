# T003 Local Install And Verification

Claim: The notarized QA artifact for the OpenAI merge is installed locally at `/Applications/Foil.app` and passes release-grade identity/signing/notarization/launch checks.

Strongest realistic failure mode: The downloaded artifact is corrupted, stale, unsigned, rejected by Gatekeeper, or not actually the app launched from `/Applications`.

Evidence:
- Download path: `/tmp/foil-openai-qa-26896782669/Foil-1.13.4-26896782669-notarized-qa/`.
- DMG: `Foil-1.13.4-26896782669-017dc25f704940eb495998d4c3048f197dfcf664-11-macos.dmg`.
- Local DMG SHA-256 matched the workflow checksum file: `88259fbedfe16e035b34c2cd4cf3a8c570e123019f70048ad55a485724c5a356`.
- `xcrun stapler validate <dmg>` returned `The validate action worked!`.
- Installed bundle values:
  - `CFBundleIdentifier`: `com.neonwatty.Foil`
  - `CFBundleShortVersionString`: `1.13.4`
  - `CFBundleVersion`: `26896782669`
- `codesign --verify --deep --strict --verbose=2 /Applications/Foil.app` returned `valid on disk` and `satisfies its Designated Requirement`.
- `spctl -a -vv -t execute /Applications/Foil.app` returned `accepted`, `source=Notarized Developer ID`, `origin=Developer ID Application: Mean Weasel LLC (B3A6AN2HA4)`.
- `open /Applications/Foil.app` launched process `4099`; `ps -p 4099 -o pid=,comm=,args=` showed `/Applications/Foil.app/Contents/MacOS/Foil`.
- The mounted DMG `/Volumes/Foil QA` was detached after install.

Residual risk / follow-up: `xcrun stapler validate /Applications/Foil.app` reports the app bundle itself has no stapled ticket. The notarized DMG is stapled and Gatekeeper accepts the installed app as `Notarized Developer ID`, matching the release-process app assessment. T004 still needs installed-app OpenAI Whisper smoke proof.
