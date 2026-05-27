# Release Process

Foil releases are manual and tag-driven. Release prep changes must go through a pull request and merge queue before a tag is created.

## Prepare a Release PR

1. Write release notes in a temporary Markdown file.
2. Run:

   ```bash
   make prepare-release VERSION=1.12.1 BUILD=33 NOTES=/path/to/release-notes.md
   ```

3. Review `CHANGELOG.md`, `package.json`, `package-lock.json`, and `Foil.xcodeproj/project.pbxproj`.
4. Open a PR and merge it through the queue after CI is green.

## Tag the Merged Commit

After the release-prep PR is merged and `main` is up to date:

```bash
git switch main
git pull --ff-only
git tag v1.12.1
git push origin v1.12.1
```

## Build and Publish

Run the `Release` workflow manually with `version` set to `1.12.1` and `build` set to `33`.

The workflow checks out `v1.12.1`, creates the GitHub Release if it does not already exist, builds a branded drag-to-Applications DMG using `.github/assets/dmg-background.png`, notarizes it, uploads the DMG and checksum, generates `appcast.xml`, and attempts the Homebrew cask update.

After the workflow completes, mount the DMG locally during release QA and confirm the Finder window uses the Foil-branded background, shows `Foil.app` on the left, and shows the Applications drop link on the right.
