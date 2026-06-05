# iOS TestFlight Upload Runbook

This runbook starts where `docs/goals/ios-testflight-archive-readiness/`
left off: the Foil iOS app can be archived and exported with correct
version/build metadata, but App Store Connect/TestFlight upload still requires
account authentication and an external upload command.

## Current State

- `altool` is available through Xcode.
- Standalone Transporter is not installed under `/Applications`.
- App Store Connect API key authentication is configured locally via a private
  key file under `~/.appstoreconnect/private_keys/`. Do not commit or print that
  file.
- App Store Connect has an iOS app record named `Foil Dictation` for bundle ID
  `com.neonwatty.FoilIOS`, Apple ID `6777069277`, SKU `foil-ios-001`.
- The first TestFlight upload succeeded on 2026-06-05 with delivery UUID
  `b6ee56d7-a91a-4183-9552-0a725a77d46e`.
- Apple reported the uploaded build as `VALID`, `APP_STORE_ELIGIBLE`,
  `is-on-app-store-connect: true`, version `1`, min OS `17.0`.
- Export compliance has been answered for the uploaded build:
  `usesNonExemptEncryption: false`.
- TestFlight build beta detail reports `internalBuildState:
  READY_FOR_BETA_TESTING` and `externalBuildState:
  READY_FOR_BETA_SUBMISSION`.
- Internal beta group `Foil Internal Testers` exists and has build
  `b6ee56d7-a91a-4183-9552-0a725a77d46e` attached.
- No tester was added to that group yet because the account has multiple
  existing beta-tester records, including duplicates, and the preview phone's
  intended TestFlight Apple ID should be chosen explicitly.
- The preview phone's App Store account was confirmed through WDA on the
  physical device, and a fresh beta tester for that account was created directly
  into `Foil Internal Testers`.
- The internal group now has one tester in `INVITED` state.
- `iPhone-preview` does not currently have TestFlight installed. Opening the
  TestFlight App Store listing reached an Apple Account password prompt, so
  installation requires human authentication on the phone.
- Regenerate `/tmp` archive/export artifacts before a future upload because
  those paths are ephemeral.

## Required Authentication

Use one of these authentication paths. Do not commit the values.

### API Key

Required values:

- API key ID
- issuer ID
- private key file `AuthKey_<api_key>.p8`

`altool` searches for private key files in:

- `./private_keys`
- `~/private_keys`
- `~/.private_keys`
- `~/.appstoreconnect/private_keys`
- `$API_PRIVATE_KEYS_DIR`

### Apple ID App Password

Required values:

- App Store Connect username
- app-specific password
- provider public ID if the account has multiple providers

The password can be supplied from keychain with:

```bash
xcrun altool --store-password-in-keychain-item <keychain_item_name> \
  -u <apple_id_email> \
  -p <app_specific_password>
```

Then commands can refer to:

```bash
-p @keychain:<keychain_item_name>
```

## Regenerate Archive And IPA

From repo root:

```bash
rm -rf /tmp/FoilIOS-TestFlightReadiness.xcarchive \
  /tmp/FoilIOS-TestFlightReadinessExport \
  /tmp/FoilIOS-TestFlightReadiness-ExportOptions.plist

/usr/libexec/PlistBuddy \
  -c 'Clear dict' \
  -c 'Add :method string app-store-connect' \
  -c 'Add :teamID string B3A6AN2HA4' \
  -c 'Add :signingStyle string automatic' \
  -c 'Add :destination string export' \
  /tmp/FoilIOS-TestFlightReadiness-ExportOptions.plist

cd FoiliOS
xcodebuild archive \
  -project FoilIOS.xcodeproj \
  -scheme FoilIOS \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath /tmp/FoilIOS-TestFlightReadiness.xcarchive \
  -allowProvisioningUpdates

xcodebuild -exportArchive \
  -archivePath /tmp/FoilIOS-TestFlightReadiness.xcarchive \
  -exportPath /tmp/FoilIOS-TestFlightReadinessExport \
  -exportOptionsPlist /tmp/FoilIOS-TestFlightReadiness-ExportOptions.plist \
  -allowProvisioningUpdates
```

Expected IPA:

```text
/tmp/FoilIOS-TestFlightReadinessExport/Foil iOS.ipa
```

## Verify IPA Metadata Before Upload

```bash
rm -rf /tmp/FoilIOS-TestFlightReadinessIPA
mkdir -p /tmp/FoilIOS-TestFlightReadinessIPA
unzip -q '/tmp/FoilIOS-TestFlightReadinessExport/Foil iOS.ipa' \
  -d /tmp/FoilIOS-TestFlightReadinessIPA

/usr/libexec/PlistBuddy \
  -c 'Print :CFBundleShortVersionString' \
  '/tmp/FoilIOS-TestFlightReadinessIPA/Payload/Foil iOS.app/Info.plist'
/usr/libexec/PlistBuddy \
  -c 'Print :CFBundleVersion' \
  '/tmp/FoilIOS-TestFlightReadinessIPA/Payload/Foil iOS.app/Info.plist'
/usr/libexec/PlistBuddy \
  -c 'Print :CFBundleShortVersionString' \
  '/tmp/FoilIOS-TestFlightReadinessIPA/Payload/Foil iOS.app/PlugIns/Foil Keyboard.appex/Info.plist'
/usr/libexec/PlistBuddy \
  -c 'Print :CFBundleVersion' \
  '/tmp/FoilIOS-TestFlightReadinessIPA/Payload/Foil iOS.app/PlugIns/Foil Keyboard.appex/Info.plist'
```

Expected values:

- app version `0.1.0`, build `1`
- keyboard extension version `0.1.0`, build `1`
- app plist has `CFBundleIconName` set to `AppIcon`
- app bundle contains `AppIcon60x60@2x.png`, `AppIcon76x76@2x~ipad.png`, and
  `Assets.car`

The app icon check matters because App Store Connect validation previously
failed with errors `90022`, `90023`, and `90713` when the IPA did not contain
the required iPhone/iPad icon files or `CFBundleIconName`.

## Validate With API Key

```bash
xcrun altool --validate-app \
  -f '/tmp/FoilIOS-TestFlightReadinessExport/Foil iOS.ipa' \
  --type ios \
  --api-key <api_key_id> \
  --api-issuer <issuer_id>
```

## Upload With API Key

Only run after validation succeeds and the build upload side effect is intended:

```bash
xcrun altool --upload-app \
  -f '/tmp/FoilIOS-TestFlightReadinessExport/Foil iOS.ipa' \
  --type ios \
  --api-key <api_key_id> \
  --api-issuer <issuer_id>
```

## Check Uploaded Build Status

Use the delivery UUID returned by upload:

```bash
xcrun altool --build-status \
  --delivery-id <delivery_uuid> \
  --api-key <api_key_id> \
  --api-issuer <issuer_id> \
  --output-format json
```

## Clear Export Compliance

When App Store Connect reports `MISSING_EXPORT_COMPLIANCE`, set the build's
non-exempt-encryption answer. Keep the JWT private and do not print the token.

```bash
curl -X PATCH \
  -H "Authorization: Bearer <jwt>" \
  -H "Content-Type: application/json" \
  -d '{"data":{"type":"builds","id":"<build_id>","attributes":{"usesNonExemptEncryption":false}}}' \
  "https://api.appstoreconnect.apple.com/v1/builds/<build_id>"
```

Expected follow-up state for the Foil iOS build:

- build `usesNonExemptEncryption: false`
- beta detail `internalBuildState: READY_FOR_BETA_TESTING`
- beta detail `externalBuildState: READY_FOR_BETA_SUBMISSION`

## Internal TestFlight Group

Create an internal group if none exists:

```bash
curl -X POST \
  -H "Authorization: Bearer <jwt>" \
  -H "Content-Type: application/json" \
  -d '{"data":{"type":"betaGroups","attributes":{"name":"Foil Internal Testers","isInternalGroup":true,"feedbackEnabled":true},"relationships":{"app":{"data":{"type":"apps","id":"6777069277"}}}}}' \
  "https://api.appstoreconnect.apple.com/v1/betaGroups"
```

Attach the uploaded build to the group:

```bash
curl -X POST \
  -H "Authorization: Bearer <jwt>" \
  -H "Content-Type: application/json" \
  -d '{"data":[{"type":"builds","id":"b6ee56d7-a91a-4183-9552-0a725a77d46e"}]}' \
  "https://api.appstoreconnect.apple.com/v1/betaGroups/<group_id>/relationships/builds"
```

Latest group receipt:

- group name: `Foil Internal Testers`
- group ID: `bcca568d-167d-44cb-b952-a410e9c9e10f`
- attached build ID: `b6ee56d7-a91a-4183-9552-0a725a77d46e`
- group build count: `1`
- group tester count: `1`
- tester state: `INVITED`

Next human action: install TestFlight on `iPhone-preview` by completing the
Apple Account password prompt on the phone, then accept the Foil Dictation
TestFlight invitation.

## Validate With Apple ID App Password

```bash
xcrun altool --validate-app \
  -f '/tmp/FoilIOS-TestFlightReadinessExport/Foil iOS.ipa' \
  --type ios \
  -u <apple_id_email> \
  -p @keychain:<keychain_item_name> \
  --provider-public-id <provider_public_id>
```

## Upload With Apple ID App Password

Only run after validation succeeds and the build upload side effect is intended:

```bash
xcrun altool --upload-app \
  -f '/tmp/FoilIOS-TestFlightReadinessExport/Foil iOS.ipa' \
  --type ios \
  -u <apple_id_email> \
  -p @keychain:<keychain_item_name> \
  --provider-public-id <provider_public_id>
```

## Latest Successful Receipt

Claim: Foil iOS can be validated and uploaded to App Store Connect/TestFlight
from this machine.

Strongest realistic failure mode: local archive/export works, but App Store
Connect rejects the package because the app record, authentication, icon
catalog, signing, version metadata, or upload pipeline is still wrong.

Evidence:

- `xcrun altool --list-apps --filter-bundle-id com.neonwatty.FoilIOS ...`
  returned App Store Connect app `6777069277`, name `Foil Dictation`.
- Local IPA inspection found `CFBundleIconName => AppIcon`, bundle ID
  `com.neonwatty.FoilIOS`, version `0.1.0`, build `1`,
  `AppIcon60x60@2x.png`, `AppIcon76x76@2x~ipad.png`, and `Assets.car`.
- `xcrun altool --validate-app ...` reported `VERIFY SUCCEEDED with no errors`.
- `xcrun altool --upload-app ...` reported `UPLOAD SUCCEEDED with no errors`
  and delivery UUID `b6ee56d7-a91a-4183-9552-0a725a77d46e`.
- `xcrun altool --build-status --delivery-id b6ee56d7-a91a-4183-9552-0a725a77d46e ...`
  reported `build-status: VALID`, `import-status: VALID`,
  `is-on-app-store-connect: true`, and `uses-non-exempt-encryption: false`.
- App Store Connect API `PATCH /v1/builds/b6ee56d7-a91a-4183-9552-0a725a77d46e`
  accepted `usesNonExemptEncryption: false`.
- App Store Connect API reported `internalBuildState:
  READY_FOR_BETA_TESTING`.
- App Store Connect API created internal group `Foil Internal Testers` and
  attached the uploaded build to it.
- WDA confirmed the preview phone's App Store account, and App Store Connect API
  created a matching beta tester directly in `Foil Internal Testers`.
- App Store Connect API reported the group has one attached build and one beta
  tester in `INVITED` state.
- `devicectl` found App Store installed but not TestFlight on `iPhone-preview`;
  opening the TestFlight App Store listing reached an Apple Account password
  prompt.

Residual risk / follow-up: App Store Connect/TestFlight may still require
human authentication on `iPhone-preview` before TestFlight can be installed and
the Foil Dictation invitation can be accepted.
