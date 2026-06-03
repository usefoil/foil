# T007 Public Release Path

Recommendation: Do not tag or publish a public release from the current local state yet.

Why:
- The OpenAI merge commit `017dc25f704940eb495998d4c3048f197dfcf664` has a successful notarized QA artifact, and that artifact is installed locally as `/Applications/Foil.app` build `26896782669`.
- Live OpenAI cloud transcription passed through `FoilE2E`.
- The new What's New Settings tab is implemented and locally tested, but it is not merged and not present in the installed notarized QA app.
- Deterministic installed Release-app OpenAI smoke remains a known gap because the canned-audio app hook is DEBUG-only.

Recommended next release slice:
1. Decide whether to add a release-safe installed-app OpenAI smoke hook for QA artifacts.
2. Open a PR with the What's New tab, and optionally the release-safe smoke hook if approved.
3. Merge through the queue after CI and cloud workflows are green.
4. Run a fresh Notarized QA Build from the merged commit.
5. Install that new QA artifact locally and rerun:
   - checksum/stapler validation
   - bundle id/version/build checks
   - `codesign --verify --deep --strict`
   - `spctl -a -vv -t execute`
   - launch path proof
   - OpenAI cloud proof, ideally from the installed Release app if the QA hook is added
6. Only then prepare a release PR/tag. Version recommendation: bump to `1.14.0` because OpenAI Whisper is user-facing provider functionality.

Release notes draft:
- Added OpenAI Whisper as a first-class cloud transcription provider.
- Added live OpenAI cloud QA coverage for the transcription path.
- Added a bundled What's New tab in Settings for recent release highlights.

Blocker: Public release should wait for merge-queue validation and a new notarized QA artifact that includes the What's New source changes.
