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

Residual risk / follow-up: App Store Connect/TestFlight may still require
post-processing review fields, tester-group setup, export compliance answers, or
manual internal distribution steps before the build appears for every tester.
