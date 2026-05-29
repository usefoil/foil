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
