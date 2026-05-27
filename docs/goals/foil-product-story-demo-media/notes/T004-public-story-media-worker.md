# T004 Worker Receipt

Result: done

## Summary

Executed the approved public credibility foundation slice.

- Added a README product preview with real Foil screenshots.
- Added a landing-page screenshots section using four verified real-app window images.
- Copied the existing verified Foil visual receipts into `site/assets/screenshots/`.
- Corrected the live `v1.12.1` GitHub Release assets from stale legacy app names to Foil-named assets.
- Added a concise Foil-focused `v1.12.1` release body.
- Updated release QA notes to match the corrected release state.
- Fixed mobile nav wrapping found during browser verification.

## Files Changed

- `README.md`
- `site/index.html`
- `site/styles.css`
- `site/assets/screenshots/foil-ready-control-center.png`
- `site/assets/screenshots/foil-setup-needed.png`
- `site/assets/screenshots/foil-onboarding-setup.png`
- `site/assets/screenshots/foil-settings-transcription.png`
- `docs/release-qa-log.md`

## Release Actions

Existing release assets were downloaded and verified before mutation:

- Existing DMG SHA-256: `4e3551cc66bda43191e2a73db61273f83d2fa50b2f26ddd85851f539f2298f9e`
- Uploaded byte-equivalent `Foil-1.12.1-macos.dmg`
- Uploaded `Foil-1.12.1-macos.dmg.sha256`
- Removed stale legacy-named `v1.12.1` DMG and checksum assets after Foil-named assets existed
- Updated release body at `https://github.com/mean-weasel/foil/releases/tag/v1.12.1`

Current release assets:

- `Foil-1.12.1-macos.dmg`
- `Foil-1.12.1-macos.dmg.sha256`
- `appcast.xml`

## Screenshot Evidence

New capture attempted with the current app build, but this Mac denied display/window capture:

```text
could not create image from window
could not create image from display
```

Fallback used the verified real-app visual receipts from `docs/goals/foil-ux-reorganization/notes/visual/`, which were previously captured from deterministic Foil UI-testing windows with `screencapture -l`.

Published screenshot assets:

- `site/assets/screenshots/foil-ready-control-center.png`
- `site/assets/screenshots/foil-setup-needed.png`
- `site/assets/screenshots/foil-onboarding-setup.png`
- `site/assets/screenshots/foil-settings-transcription.png`

## Verification

Passed:

```text
make build
make test-provider-qa
```

Passed release verification:

```text
gh release view v1.12.1 --repo mean-weasel/foil --json name,tagName,url,body,assets,isDraft,isPrerelease,publishedAt
```

The release is titled `Foil 1.12.1`, has a Foil-focused body, and only Foil-named DMG/checksum assets plus `appcast.xml`.

Passed public text check:

```text
rg -n "GroqTalk|Demo media has not been published yet|GroqTalk-1.12.1" README.md site docs/release-qa-log.md
```

Result: no matches.

Passed asset check:

```text
find site/assets -maxdepth 3 -type f | sort
```

Confirmed `foil-mark.svg` plus four screenshot PNGs.

Passed browser preview check at `http://127.0.0.1:8008/`:

- page title remains `Foil — Push-to-talk speech to text for macOS`
- screenshots section exists
- all six page images load with non-zero natural size
- no `GroqTalk` text
- no old demo-media placeholder text
- mobile viewport `390x844` has zero horizontal overflow
- mobile nav wraps instead of clipping `GitHub`

Cleanup:

```text
pgrep -x Foil || true
lsof -ti tcp:8008 || true
```

No Foil process or local preview server remained.

## Notes

This slice improves screenshot/demo credibility, but it does not yet provide a short video demo. Because live desktop recording can expose private content, video remains deferred until the owner opts into a clean capture flow.
