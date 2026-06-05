# Foil iOS TestFlight Archive Readiness

## Intent

Make the Foil iOS prototype archive-ready enough for an internal TestFlight attempt, or produce a precise blocker if Apple account, signing, export, or App Store Connect state prevents a responsible upload.

## Oracle

The goal is complete when a fresh branch from `codex/ios-keyboard-prototype` either:

- produces verified archive/export metadata with version/build values aligned between `project.yml`, generated plists, and the built archive; or
- records the exact command, log, account/signing blocker, and next human action needed.

The proof must include branch/PR links, `xcodegen`/Xcode build or archive evidence, direct plist/archive metadata inspection, secret/private scan, and a final audit.

## Starting Facts

- PR #229 has been merged into `codex/ios-keyboard-prototype` as merge commit `b68c511`.
- Scout evidence from the conveyor found:
  - `project.yml` declares `MARKETING_VERSION: 0.1.0`.
  - `project.yml` declares `CURRENT_PROJECT_VERSION: 1`.
  - generated `FoilIOSApp/Generated/Info.plist` currently reports `CFBundleShortVersionString` as `1.0`.
  - generated `FoilIOSApp/Generated/Info.plist` reports `CFBundleVersion` as `1`.
  - no `ExportOptions*.plist`, `.xcarchive`, or `.ipa` artifact exists under `FoiliOS`.
- Physical devices are connected, but WDA was not listening at the start of this board.
- Do not claim a TestFlight upload without App Store Connect/export proof.

## Non-Goals

- Do not test Messages unless a dedicated safe self/test thread exists.
- Do not add production account/server auth.
- Do not print, store, or commit API keys, transcript bodies, private target-app content, or raw private accessibility trees.
- Do not make unrelated UI/product changes while fixing archive metadata.

## Starter Command

`/goal Follow docs/goals/ios-testflight-archive-readiness/goal.md.`
