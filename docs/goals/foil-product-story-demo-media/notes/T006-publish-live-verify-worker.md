# T006 Worker Receipt

Result: done

## Summary

Published the product story/media slice through PR #146, merged it through the merge queue, and verified the live GitHub Pages site plus release-facing surfaces.

## Publish Evidence

- Created branch `codex/foil-product-story-demo-media`.
- Committed `3ef4044` with public surface, screenshot, and GoalBuddy receipt changes.
- Opened PR #146: `https://github.com/mean-weasel/foil/pull/146`
- PR CI passed:
  - Detect Changed Paths
  - Build
  - Unit Tests
  - Focused UI Smoke
  - CI Gate
- Enqueued PR #146 into the merge queue via GitHub GraphQL.
- Merge queue CI passed on `gh-readonly-queue/main/pr-146-*`:
  - Build
  - Unit Tests
  - Focused UI Smoke
  - CI Gate
- PR #146 merged at `2026-05-27T13:25:47Z`.
- Merged commit: `ccba2abe6aeb91805bd68680471e5fb7e08810a4`.
- Pulled `main` fast-forward locally.

## Live Verification

Landing Page workflow:

- Run `26513976016`
- Result: success

Live site checked at:

```text
https://mean-weasel.github.io/foil/?verify=20260527-1326
```

Browser verification results:

- page title: `Foil — Push-to-talk speech to text for macOS`
- screenshots section exists
- heading: `A real menu bar workflow`
- all six page images loaded with non-zero natural size
- no `GroqTalk` text on the page
- no `Demo media has not been published yet` text on the page
- mobile viewport `390x844` has zero horizontal overflow
- mobile nav wraps without clipping the GitHub item

Release verification:

- `v1.12.1` release remains titled `Foil 1.12.1`
- release body is Foil-focused
- assets are `Foil-1.12.1-macos.dmg`, `Foil-1.12.1-macos.dmg.sha256`, and `appcast.xml`

## Commands

Passed:

```text
git push -u origin codex/foil-product-story-demo-media
gh pr create --repo mean-weasel/foil ...
gh pr view 146 --repo mean-weasel/foil --json ...
gh run watch 26513536274 --repo mean-weasel/foil --exit-status
gh run watch 26513976016 --repo mean-weasel/foil --exit-status
gh release view v1.12.1 --repo mean-weasel/foil --json name,tagName,url,body,assets,isDraft,isPrerelease,publishedAt
Browser live checks for desktop and 390x844 mobile
```

## Notes

`gh pr merge` could not add the PR to the queue because repository auto-merge is disabled and direct/admin merge is blocked by rules requiring the queue. The PR was queued successfully with GitHub's `enqueuePullRequest` GraphQL mutation.
