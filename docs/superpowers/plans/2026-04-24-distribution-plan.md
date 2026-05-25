# Distribution Implementation Plan (Code Signing, DMG, Homebrew)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Automate building a signed, notarized DMG attached to each GitHub release, and create a Homebrew Cask for easy installation.

**Architecture:** The existing `deploy.yml` workflow (semantic-release) gets a new `build-dmg` job that runs after a release is created. It builds an Xcode archive with Developer ID signing, packages a DMG, notarizes it with Apple, and uploads it as a release asset. A separate `homebrew-tap` repo hosts the Cask formula pointing to the DMG URL.

**Tech Stack:** GitHub Actions, `xcodebuild archive/export`, `create-dmg`, `xcrun notarytool`, `xcrun stapler`, Homebrew Cask

---

## File Structure

| File | Action | Responsibility |
|------|--------|---------------|
| `.github/workflows/deploy.yml` | Modify | Add `build-dmg` job after semantic-release |
| `.github/scripts/import-cert.sh` | Create | Import signing certificate into CI keychain |
| `ExportOptions.plist` | Create | Xcode archive export options for Developer ID |
| `neonwatty/homebrew-tap` (separate repo) | Create | Homebrew Cask formula |

---

### Task 1: Configure GitHub Secrets

**Files:** None (GitHub Settings only)

This task is manual — the engineer must configure secrets in the GitHub repo settings before the CI workflow can sign and notarize.

- [ ] **Step 1: Export your Developer ID Application certificate as a .p12 file**

In Keychain Access:
1. Find "Developer ID Application: [Your Name]" in the login keychain
2. Right-click → Export → save as `certificate.p12` with a strong password
3. Base64-encode it:

```bash
base64 -i certificate.p12 -o certificate-base64.txt
```

- [ ] **Step 2: Create an app-specific password for notarization**

Go to [appleid.apple.com](https://appleid.apple.com/) → Sign-In and Security → App-Specific Passwords → Generate one named "Foil Notarization".

- [ ] **Step 3: Add secrets to GitHub repo**

Go to `github.com/neonwatty/foil` → Settings → Secrets and variables → Actions → New repository secret:

| Secret Name | Value |
|------------|-------|
| `DEVELOPER_ID_CERT_BASE64` | Contents of `certificate-base64.txt` |
| `DEVELOPER_ID_CERT_PASSWORD` | Password you set when exporting the .p12 |
| `APPLE_TEAM_ID` | Your 10-character Team ID (from developer.apple.com → Membership) |
| `APPLE_ID` | Your Apple ID email |
| `APPLE_ID_PASSWORD` | The app-specific password from Step 2 |

- [ ] **Step 4: Delete the local certificate files**

```bash
rm certificate.p12 certificate-base64.txt
```

---

### Task 2: Certificate Import Script

**Files:**
- Create: `.github/scripts/import-cert.sh`

- [ ] **Step 1: Create the certificate import script**

Create `.github/scripts/import-cert.sh`:

```bash
#!/bin/bash
set -euo pipefail

# Create a temporary keychain for CI
KEYCHAIN_PATH="$RUNNER_TEMP/build.keychain-db"
KEYCHAIN_PASSWORD="$(openssl rand -base64 32)"

security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"

# Import the certificate
echo "$DEVELOPER_ID_CERT_BASE64" | base64 --decode > "$RUNNER_TEMP/certificate.p12"
security import "$RUNNER_TEMP/certificate.p12" \
    -k "$KEYCHAIN_PATH" \
    -P "$DEVELOPER_ID_CERT_PASSWORD" \
    -T /usr/bin/codesign \
    -T /usr/bin/security

# Allow codesign to access the keychain without prompts
security set-key-partition-list -S apple-tool:,apple: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"

# Add the temporary keychain to the search list
security list-keychains -d user -s "$KEYCHAIN_PATH" $(security list-keychains -d user | tr -d '"')

# Clean up the certificate file
rm -f "$RUNNER_TEMP/certificate.p12"

echo "KEYCHAIN_PATH=$KEYCHAIN_PATH" >> "$GITHUB_ENV"
```

- [ ] **Step 2: Make the script executable**

```bash
chmod +x .github/scripts/import-cert.sh
```

- [ ] **Step 3: Commit**

```bash
git add .github/scripts/import-cert.sh
git commit -m "ci: add certificate import script for code signing"
```

---

### Task 3: Export Options Plist

**Files:**
- Create: `ExportOptions.plist`

- [ ] **Step 1: Create ExportOptions.plist**

Create `ExportOptions.plist` in the project root:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>signingStyle</key>
    <string>automatic</string>
    <key>teamID</key>
    <string>$(APPLE_TEAM_ID)</string>
</dict>
</plist>
```

Note: The `$(APPLE_TEAM_ID)` placeholder will be replaced by `sed` in the workflow before use.

- [ ] **Step 2: Commit**

```bash
git add ExportOptions.plist
git commit -m "ci: add export options plist for Developer ID signing"
```

---

### Task 4: DMG Build and Notarize Workflow

**Files:**
- Modify: `.github/workflows/deploy.yml`

- [ ] **Step 1: Update deploy.yml to output release info from semantic-release**

In `.github/workflows/deploy.yml`, update the release job to capture whether a new release was created. Replace the existing `release` job with:

```yaml
jobs:
  release:
    name: Semantic Release
    runs-on: ubuntu-latest
    timeout-minutes: 10
    outputs:
      new_release_published: ${{ steps.semantic.outputs.new_release_published }}
      new_release_version: ${{ steps.semantic.outputs.new_release_version }}
    steps:
      - name: Checkout code
        uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Setup Node.js
        uses: actions/setup-node@v4
        with:
          node-version: 22
          cache: npm

      - name: Install dependencies
        run: npm ci

      - name: Run semantic release
        id: semantic
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: npx semantic-release
```

- [ ] **Step 2: Add the build-dmg job**

Add after the `release` job in `deploy.yml`:

```yaml
  build-dmg:
    name: Build DMG
    runs-on: macos-15
    timeout-minutes: 30
    needs: [release]
    if: needs.release.outputs.new_release_published == 'true'

    steps:
      - name: Checkout code
        uses: actions/checkout@v4
        with:
          ref: v${{ needs.release.outputs.new_release_version }}

      - name: Select Xcode
        run: sudo xcode-select -s /Applications/Xcode_16.3.app/Contents/Developer

      - name: Import signing certificate
        env:
          DEVELOPER_ID_CERT_BASE64: ${{ secrets.DEVELOPER_ID_CERT_BASE64 }}
          DEVELOPER_ID_CERT_PASSWORD: ${{ secrets.DEVELOPER_ID_CERT_PASSWORD }}
        run: .github/scripts/import-cert.sh

      - name: Prepare export options
        env:
          APPLE_TEAM_ID: ${{ secrets.APPLE_TEAM_ID }}
        run: sed -i '' "s/\$(APPLE_TEAM_ID)/$APPLE_TEAM_ID/" ExportOptions.plist

      - name: Archive
        run: |
          xcodebuild archive \
            -scheme Foil \
            -configuration Release \
            -destination 'platform=macOS' \
            -archivePath "$RUNNER_TEMP/Foil.xcarchive" \
            CODE_SIGN_IDENTITY="Developer ID Application" \
            DEVELOPMENT_TEAM="${{ secrets.APPLE_TEAM_ID }}"

      - name: Export app
        run: |
          xcodebuild -exportArchive \
            -archivePath "$RUNNER_TEMP/Foil.xcarchive" \
            -exportPath "$RUNNER_TEMP/export" \
            -exportOptionsPlist ExportOptions.plist

      - name: Verify code signature
        run: |
          codesign --verify --deep --strict "$RUNNER_TEMP/export/Foil.app"
          echo "Code signature verified"

      - name: Install create-dmg
        run: brew install create-dmg

      - name: Create DMG
        env:
          VERSION: ${{ needs.release.outputs.new_release_version }}
        run: |
          create-dmg \
            --volname "Foil" \
            --window-pos 200 120 \
            --window-size 600 400 \
            --icon-size 100 \
            --icon "Foil.app" 150 190 \
            --app-drop-link 450 190 \
            "$RUNNER_TEMP/Foil-${VERSION}-macos.dmg" \
            "$RUNNER_TEMP/export/Foil.app"

      - name: Notarize DMG
        env:
          APPLE_ID: ${{ secrets.APPLE_ID }}
          APPLE_ID_PASSWORD: ${{ secrets.APPLE_ID_PASSWORD }}
          APPLE_TEAM_ID: ${{ secrets.APPLE_TEAM_ID }}
          VERSION: ${{ needs.release.outputs.new_release_version }}
        run: |
          xcrun notarytool submit \
            "$RUNNER_TEMP/Foil-${VERSION}-macos.dmg" \
            --apple-id "$APPLE_ID" \
            --team-id "$APPLE_TEAM_ID" \
            --password "$APPLE_ID_PASSWORD" \
            --wait

          xcrun stapler staple "$RUNNER_TEMP/Foil-${VERSION}-macos.dmg"
          echo "Notarization complete"

      - name: Upload DMG to release
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          VERSION: ${{ needs.release.outputs.new_release_version }}
        run: |
          gh release upload "v${VERSION}" \
            "$RUNNER_TEMP/Foil-${VERSION}-macos.dmg" \
            --clobber

      - name: Cleanup keychain
        if: always()
        run: security delete-keychain "$KEYCHAIN_PATH" 2>/dev/null || true
```

- [ ] **Step 3: Add semantic-release exec plugin for output capture**

The `semantic-release` outputs (`new_release_published`, `new_release_version`) require the `@semantic-release/exec` plugin or checking the git tag after semantic-release runs. The simpler approach is to check for a new tag:

Replace the semantic release step with:

```yaml
      - name: Run semantic release
        id: semantic
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          BEFORE_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "none")
          npx semantic-release
          AFTER_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "none")
          if [ "$BEFORE_TAG" != "$AFTER_TAG" ]; then
            echo "new_release_published=true" >> "$GITHUB_OUTPUT"
            echo "new_release_version=${AFTER_TAG#v}" >> "$GITHUB_OUTPUT"
          else
            echo "new_release_published=false" >> "$GITHUB_OUTPUT"
          fi
```

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/deploy.yml
git commit -m "ci: add DMG build, code signing, and notarization to release workflow"
```

---

### Task 5: Homebrew Tap

**Files:** New repo `neonwatty/homebrew-tap`

- [ ] **Step 1: Create the homebrew-tap repo on GitHub**

```bash
gh repo create neonwatty/homebrew-tap --public --description "Homebrew tap for neonwatty projects"
```

- [ ] **Step 2: Clone and create the cask formula**

```bash
cd /tmp
git clone git@github.com:neonwatty/homebrew-tap.git
cd homebrew-tap
mkdir -p Casks
```

- [ ] **Step 3: Create the cask formula**

Create `Casks/foil.rb`:

```ruby
cask "foil" do
  version "1.0.0"
  sha256 "PLACEHOLDER"

  url "https://github.com/neonwatty/foil/releases/download/v#{version}/Foil-#{version}-macos.dmg"
  name "Foil"
  desc "macOS menu bar speech-to-text powered by Groq Whisper"
  homepage "https://github.com/neonwatty/foil"

  depends_on macos: ">= :sonoma"

  app "Foil.app"

  zap trash: [
    "~/Library/Application Support/Foil",
  ]
end
```

Note: The `version` and `sha256` will be updated after the first DMG release is built. The `sha256` placeholder will cause `brew install` to fail until updated — this is intentional as a reminder.

- [ ] **Step 4: Add a README to the tap repo**

Create `README.md`:

```markdown
# Homebrew Tap

Homebrew formulae and casks for [neonwatty](https://github.com/neonwatty) projects.

## Install

```
brew tap neonwatty/tap
```

## Available Casks

| Cask | Description |
|------|-------------|
| `foil` | macOS menu bar speech-to-text powered by Groq Whisper |

### Foil

```
brew install --cask foil
```
```

- [ ] **Step 5: Commit and push**

```bash
cd /tmp/homebrew-tap
git add .
git commit -m "feat: add foil cask formula"
git push origin main
```

- [ ] **Step 6: Update the cask after first DMG release**

After the first `feat:` or `fix:` commit triggers a new release with a DMG:

1. Download the DMG:
```bash
VERSION="1.1.0"  # whatever the new version is
curl -L -o /tmp/Foil.dmg "https://github.com/neonwatty/foil/releases/download/v${VERSION}/Foil-${VERSION}-macos.dmg"
```

2. Get the SHA256:
```bash
shasum -a 256 /tmp/Foil.dmg
```

3. Update `Casks/foil.rb` with the new version and SHA256.

4. Commit and push to the tap repo.

- [ ] **Step 7: Test the install**

```bash
brew tap neonwatty/tap
brew install --cask foil
```

Expected: Foil.app appears in /Applications.
