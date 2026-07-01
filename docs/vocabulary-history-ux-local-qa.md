# Vocabulary History UX Local QA

Date: 2026-07-01
Branch: `codex/vocabulary-history-ux`

## Local App Launch

```sh
xcodebuild build -project Foil.xcodeproj -scheme Foil -configuration Debug -destination 'platform=macOS'
open -n "$HOME/Library/Developer/Xcode/DerivedData/Foil-ebuxbvgmspyykabsrfclwquwxbdi/Build/Products/Debug/Foil.app" --args --ui-testing --reset-defaults --seed-history --seed-history-reclean-enabled --show-app-shell
```

## Workflows

### History App Filters

Claim: History source-app filters narrow seeded records without hiding app metadata.

Strongest realistic failure mode: filter buttons render, but selecting them leaves unrelated records visible or removes the row app labels.

Evidence: Computer Use accessibility snapshots showed:

- `Mail` selected with only `Second searchable transcript.` and `just now · Mail`.
- `Messages` selected with only `Seeded transcript for UI testing.` and `just now · Messages`.

Residual risk / follow-up: None for seeded filter behavior.

### History Phrase Selection

Claim: selecting History transcript tokens opens a Vocabulary sheet prefilled with the selected phrase.

Strongest realistic failure mode: the inline selected phrase is correct, but the sheet opens with a blank editable phrase field.

Evidence: Manual testing initially reproduced this failure. After the fix, Computer Use showed the sheet field `history.vocabulary.writtenAsField` with `Value: Second searchable`.

Residual risk / follow-up: Covered by focused UI test assertions for single-token and multi-token selections.

### Save And Re-clean

Claim: Save and Re-clean saves the correction and updates the selected History row.

Strongest realistic failure mode: the correction is saved but the current History row remains stale.

Evidence: In the seeded local app, selecting `Second searchable`, entering `Supabase`, and clicking `Save and Re-clean` updated the Mail row to `Re-cleaned History transcript uses Supabase.`.

Residual risk / follow-up: Deterministic seeded cleanup only; live provider behavior is covered by provider QA.

### Settings Vocabulary Management

Claim: Cleanup settings expose saved Vocabulary corrections and allow add/delete management.

Strongest realistic failure mode: Save and Re-clean updates History but does not persist a settings-visible Vocabulary correction, or settings add/delete leaves stale rows.

Evidence: Cleanup settings showed `Second searchable -> Supabase`. Adding `Foilism -> Foil term` created a second row and cleared inputs; deleting that row removed only the throwaway row and left `Second searchable -> Supabase`.

Residual risk / follow-up: None for settings add/delete with seeded state.

### Preferred Terms

Claim: Preferred terms accepts multiline terms in Cleanup settings.

Strongest realistic failure mode: multiline entry appears editable but does not update the control value.

Evidence: Computer Use set `settings.preferredTermsEditor` to:

```text
Supabase
Foil UX
```

The accessibility value and visible text both reflected the two lines.

Residual risk / follow-up: None for local settings editing.

## Automated Regression

```sh
xcodebuild test -project Foil.xcodeproj -scheme Foil -destination 'platform=macOS' \
  -only-testing:FoilUITests/FoilUITests/testHistoryComponentHostDetailAllowsEditingAndExport \
  -only-testing:FoilUITests/FoilUITests/testHistoryComponentHostSaveAndRecleanVocabularySelection
```

Result: passed after adding assertions that the Vocabulary sheet pre-fills `Second searchable` and `Second`.
