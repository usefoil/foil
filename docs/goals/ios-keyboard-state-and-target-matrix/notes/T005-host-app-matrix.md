# T005 Host-App Matrix

Date: 2026-06-04
Device: iPhone-preview, iOS 26.4.2
Build: `/tmp/foil-ios-state-derived/Build/Products/Debug-iphoneos/Foil iOS.app`
Branch: `codex/ios-keyboard-state-store`

## Preconditions

- Foil Keyboard is installed and selected as a custom keyboard.
- Settings > General > Keyboard > Keyboards > Foil Keyboard > Allow Full Access is enabled.
- Each insertion row used a unique safe transcript seeded into `group.com.neonwatty.FoilIOS` at `Library/foil-keyboard-snapshot.json`.
- Evidence avoids preserving private app accessibility trees. Receipts record only safe transcript strings, element states, and copied Foil App Group state.

## Matrix

| App / Field | Setup | Result | Evidence | Residual Risk |
| --- | --- | --- | --- | --- |
| Notes / existing safe test note | Seeded `Foil matrix notes 2026-06-04T18:23:58Z`; focused the open Notes editor; selected Foil Keyboard. | Pass: inserted once and reset persisted. | WDA source count for the safe transcript in the Notes text view was exactly 1. Keyboard after tap showed `Ready`, `Insert latest (no transcript)`, `enabled=false`. Copied canonical JSON showed `phase=idle`, `message=Ready`, no transcript. | The note already contained prior safe test strings, so receipt relies on unique transcript occurrence count rather than a blank field. |
| Safari / address-search field | Launched Safari on `https://example.com`; seeded `Foil matrix safari 2026-06-04T18:26:11Z`; focused the address field; selected Foil Keyboard. | Pass: inserted into the focused address/search field and reset persisted. | WDA source had an `XCUIElementTypeTextField` with `label=Address`, `name=URL`, and value equal to the safe transcript. Keyboard after tap showed `Ready`, `Insert latest (no transcript)`, `enabled=false`. Copied canonical JSON showed `phase=idle`, `message=Ready`, no transcript. | Safari mirrors focused address text into multiple accessibility attributes; the receipt uses the actual Address text-field value rather than total raw source occurrence count. |
| Reminders / new reminder title | In the currently open Reminders list, tapped `New Reminder`; seeded `Foil matrix reminder 2026-06-04T18:28:20Z`; selected Foil Keyboard. | Pass: inserted into a new reminder title exactly once and reset persisted. | WDA source showed a `Title` text field with the safe transcript and source occurrence count 1. Keyboard after tap showed `Ready`, `Insert latest (no transcript)`, `enabled=false`. Copied canonical JSON showed `phase=idle`, `message=Ready`, no transcript. | This added a safe test reminder to the user's active list. Surrounding reminder content was not recorded in the receipt. |
| Secure field / Foil iOS harness | Added and focused `secure-rejection-field` in Foil iOS with a pending transcript `Foil matrix secure 2026-06-04T18:29:46Z`. | Pass as expected rejection: iOS showed the Apple keyboard and did not present Foil Keyboard. | WDA source after focusing the secure field: `secure_field_present=true`, `foil_keyboard_present=false`, `apple_keyboard_present=true`, visible key sample `q,w,e,r,t,y,u,i`. Canonical JSON remained `phase=complete` because no insert occurred; it was then cleaned back to idle. | The secure-field row uses a local harness rather than a third-party app password field to avoid exposing private data. |
| Messages / compose field | Not run. | Skipped by design. | The board requires Messages only if the operator opens a safe self/test thread; no such thread was provided during this run. | Needs a user-provided safe thread or test account before automation. |

## Checks

- `git diff --check -- FoiliOS docs/goals/ios-keyboard-state-and-target-matrix`: pass.
- Secret scan over `FoiliOS` and this goal: no secret values found; hits were limited to env var names and the Authorization header template.
- Final build/install: pass.
- Build log note: AppIntents metadata extraction warning remains present: `Metadata extraction skipped. No AppIntents.framework dependency found.`
