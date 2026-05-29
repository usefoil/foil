# Release Process

Foil releases are manual and tag-driven. Release prep changes must go through a pull request and merge queue before a tag is created.

## Release Secrets

The `Release` workflow expects Apple signing/notarization secrets plus
`HOMEBREW_TAP_TOKEN`, a GitHub token with write access to
`mean-weasel/homebrew-foil`. The Homebrew step falls back to `GITHUB_TOKEN` if
the tap token is unavailable, but `GITHUB_TOKEN` cannot push to the separate tap
repository.

## Prepare a Release PR

1. Write release notes in a temporary Markdown file.
2. Run:

   ```bash
   make prepare-release VERSION=1.12.2 BUILD=34 NOTES=/path/to/release-notes.md
   ```

3. Review `CHANGELOG.md`, `package.json`, `package-lock.json`, and `Foil.xcodeproj/project.pbxproj`.
4. Open a PR and merge it through the queue after CI is green.

## Tag the Merged Commit

After the release-prep PR is merged and `main` is up to date:

```bash
git switch main
git pull --ff-only
git tag v1.12.2
git push origin v1.12.2
```

## Build and Publish

Run the `Release` workflow manually with `version` set to `1.12.2` and `build` set to `34`.

The workflow checks out `v1.12.2`, creates the GitHub Release if it does not already exist, builds a branded drag-to-Applications DMG using `.github/assets/dmg-background.png`, notarizes it, uploads the DMG and checksum, generates `appcast.xml`, and attempts the Homebrew cask update.

The Homebrew cask update is intentionally `continue-on-error`: a tap failure
should not block publishing a signed, notarized GitHub release. If that step
warns or fails, treat it as required manual follow-up before announcing the
release through Homebrew: update `mean-weasel/homebrew-foil` with the released
version and DMG SHA-256, then verify `brew info --cask mean-weasel/foil/foil`
shows the new version.

After the workflow completes, mount the DMG locally during release QA and confirm the Finder window uses the Foil-branded background, shows `Foil.app` on the left, and shows the Applications drop link on the right.

## Required Production Setup QA

Before announcing a release as Homebrew-ready, complete the production install
and permission setup gates in `docs/release-qa-log.md`.

1. Install the public cask in a disposable app directory and verify the shipped
   identity:

   ```bash
   brew tap mean-weasel/foil https://github.com/mean-weasel/homebrew-foil
   brew info --cask mean-weasel/foil/foil
   brew install --cask --appdir=/tmp/foil-release-apps mean-weasel/foil/foil
   /usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' /tmp/foil-release-apps/Foil.app/Contents/Info.plist
   /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' /tmp/foil-release-apps/Foil.app/Contents/Info.plist
   /usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' /tmp/foil-release-apps/Foil.app/Contents/Info.plist
   spctl -a -vv -t execute /tmp/foil-release-apps/Foil.app
   codesign --verify --deep --strict --verbose=2 /tmp/foil-release-apps/Foil.app
   ```

   Expected result: bundle id is `com.neonwatty.Foil`, version/build match the
   release, Gatekeeper reports `Notarized Developer ID`, and deep strict
   codesign verification passes.

2. Install or reinstall the same cask into `/Applications`, launch
   `/Applications/Foil.app`, and run `make guide-installed-permissions-qa`.
   Record the helper output, installed version/build, signature, notarization
   result, launch result, and whether the active process path is
   `/Applications/Foil.app/Contents/MacOS/Foil`.

3. On a fresh macOS account, VM, spare Mac, or disposable user, run the real TCC
   matrix in `docs/fresh-machine-homebrew-onboarding-smoke.md`. Do not run
   destructive `tccutil reset` commands on a daily-driver account without
   explicit operator approval. If a disposable account is used and a reset is
   approved, scope it to Foil:

   ```bash
   tccutil reset Accessibility com.neonwatty.Foil
   tccutil reset ListenEvent com.neonwatty.Foil
   tccutil reset Microphone com.neonwatty.Foil
   ```

4. Record every row in `docs/release-qa-log.md`, including failures and exact
   visible app text. A release is not setup-permission ready until the matrix
   proves that Accessibility and Microphone readiness update while onboarding is
   open and that the final `Get Started` button becomes enabled once all setup
   requirements are ready.
