# T002 Notarized QA Dispatch

Claim: A Notarized QA Build was dispatched and completed successfully for the OpenAI merge commit.

Strongest realistic failure mode: The workflow succeeded for `main` but checked out a different commit than the OpenAI merge, producing a stale artifact.

Evidence:
- `gh workflow run "Notarized QA Build" --ref main -f ref=017dc25f704940eb495998d4c3048f197dfcf664` returned run URL `https://github.com/mean-weasel/foil/actions/runs/26896782669`.
- `gh run view 26896782669 --json ...` reported `headSha` as `017dc25f704940eb495998d4c3048f197dfcf664`, event `workflow_dispatch`, branch `main`.
- `gh run watch 26896782669 --exit-status` completed successfully. The `Build Notarized QA DMG` job completed in `2m53s`.
- Actions artifact API reported artifact `Foil-1.13.4-26896782669-notarized-qa`, created `2026-06-03T16:01:23Z`, not expired.

Residual risk / follow-up: The workflow success does not by itself prove local install or launch. T003 covers checksum, stapler, copy to `/Applications`, codesign, Gatekeeper, and process path.
