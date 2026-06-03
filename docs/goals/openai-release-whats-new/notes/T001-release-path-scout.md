# T001 Release Path Scout

Claim: The current release/notarization/install path is mapped well enough to proceed to a notarized QA build for the OpenAI Whisper merge.

Strongest realistic failure mode: A prior notarized QA build or public release already contains the OpenAI merge, so dispatching another QA workflow would be unnecessary churn.

Evidence:
- `git rev-parse HEAD` returned `017dc25f704940eb495998d4c3048f197dfcf664`.
- `git show -s --format='%H%n%ci%n%s' 017dc25f704940eb495998d4c3048f197dfcf664` showed merge commit date `2026-06-03 14:24:30 +0000`.
- `gh release view --json tagName,name,publishedAt,targetCommitish,isDraft,isPrerelease,url` showed latest public release `v1.13.4`, published `2026-05-31T13:08:39Z`.
- `gh run list --workflow "Notarized QA Build" --limit 10 --json ...` showed newest QA run `26852720360` at `b39572f92f8d078b8506341990a1753505adbb04`, created `2026-06-02T22:51:08Z`, before the OpenAI merge.
- `/Applications/Foil.app` currently reports bundle id `com.neonwatty.Foil`, version `1.13.4`, build `26852720360`, matching the pre-merge QA/public build family rather than a new OpenAI QA artifact.

Workflow inputs:
- `.github/workflows/notarized-qa.yml` supports only `workflow_dispatch`.
- Required input: `ref`.
- Optional inputs: `version`, `build`.
- The QA workflow uploads `Foil-${version}-${build}-notarized-qa` containing the DMG and checksum.

Installed-app validation commands:
- `/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' /Applications/Foil.app/Contents/Info.plist`
- `/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' /Applications/Foil.app/Contents/Info.plist`
- `/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' /Applications/Foil.app/Contents/Info.plist`
- `spctl -a -vv -t execute /Applications/Foil.app`
- `codesign --verify --deep --strict --verbose=2 /Applications/Foil.app`
- Launch and verify the active process path is `/Applications/Foil.app/Contents/MacOS/Foil`.

Residual risk / follow-up: GitHub Actions could still fail because signing/notarization secrets are unavailable or Apple notarization is temporarily unavailable. T002 should dispatch `Notarized QA Build` for exact ref `017dc25f704940eb495998d4c3048f197dfcf664` and capture the run URL.
