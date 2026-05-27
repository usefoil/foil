# T003 Judge Receipt

Result: approved

## Decision

The first Worker package should be a public credibility foundation slice:

1. Correct release-facing contradictions around `v1.12.1` asset names.
2. Land a small deterministic real-app screenshot set.
3. Wire those screenshots into README and the static landing page with provider-neutral product story copy.

This is the largest safe useful slice because T001 found public contradictions, T002 found a safe screenshot workflow, and the goal oracle requires both coherent story and verified demo/screenshot artifacts. A copy-only slice would be too thin; a full video demo would require owner opt-in and can wait.

## Worker Objective

Fix Foil's public story/demo credibility by replacing stale demo-media absence copy with verified real-app screenshots, updating README/site copy to match current provider behavior and install paths, and reconciling `v1.12.1` release-facing asset naming with live GitHub release reality.

## Allowed Files

- `README.md`
- `site/index.html`
- `site/styles.css`
- `site/assets/**`
- `docs/release-qa-log.md`
- `docs/goals/foil-product-story-demo-media/state.yaml`
- `docs/goals/foil-product-story-demo-media/notes/**`

## External Actions Allowed

- Read `v1.12.1` release metadata with `gh release view`.
- Download existing `v1.12.1` release assets for verification/renaming only.
- Upload correctly named `Foil-1.12.1-macos.dmg` and `Foil-1.12.1-macos.dmg.sha256` if they can be derived byte-for-byte from the existing assets.
- Delete the stale `GroqTalk-1.12.1-*` release assets only after the correctly named Foil assets are present on the release and checksums/digests match.
- Add a concise release body describing Foil 1.12.1 and linking install paths.

## Verify

- `make test-provider-qa`
- `gh release view v1.12.1 --repo mean-weasel/foil --json name,tagName,url,body,assets,isDraft,isPrerelease,publishedAt`
- `rg -n "GroqTalk|Demo media has not been published yet|GroqTalk-1.12.1" README.md site docs/release-qa-log.md`
- `find site/assets -maxdepth 3 -type f`
- `node /Users/neonwatty/.codex/plugins/cache/goalbuddy/goalbuddy/0.3.7/skills/goalbuddy/scripts/check-goal-state.mjs docs/goals/foil-product-story-demo-media/state.yaml`

If the landing page is materially changed, also perform a browser/local static preview check and record the URL or screenshot evidence in the Worker receipt.

## Stop If

- A capture would include private desktop content, API keys, personal transcripts, diagnostics, or local secrets.
- The Worker cannot capture real seeded app windows without requiring owner desktop/video consent.
- Existing release assets cannot be verified before upload/rename.
- `gh` lacks permission to mutate the release.
- Needed edits fall outside `allowed_files`.
- Claims would exceed current app behavior or verified release facts.

## Deferred Work

- Full desktop/video demo.
- Live Groq or live microphone demo.
- Abstract Edison-cylinder brand art.
- App UI redesign beyond media/copy integration.
