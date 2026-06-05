# iOS TestFlight Upload Runbook

This runbook starts where `docs/goals/ios-testflight-archive-readiness/`
left off: the Foil iOS app can be archived and exported with correct
version/build metadata, but App Store Connect/TestFlight upload still requires
account authentication and an external upload command.

## Current State

- `altool` is available through Xcode.
- Standalone Transporter is not installed under `/Applications`.
- No App Store Connect-like environment variables were present during the latest check.
- No known App Store Connect keychain item names were found during presence-only checks.
- No `AuthKey_*.p8` files were found in the standard `altool` search locations.
- The prior exported IPA under `/tmp` was not present during the latest check, so regenerate before upload.

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

## Current Blocker

The latest unattended check stopped before validation/upload because no safe
local App Store Connect authentication material was visible:

- no matching App Store Connect environment variables;
- no matching known keychain item names;
- no `AuthKey_*.p8` files in standard search locations;
- `altool --list-providers` failed with missing JWT or username/app-password authentication.

Next human action: provide either an App Store Connect API key/issuer/private
key file or an Apple ID app-specific password plus provider public ID, then rerun
validation before upload.
