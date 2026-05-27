# Foil Product Story and Demo Media

## Objective

Improve Foil's public product story and demo-media credibility by producing a coherent, verified set of story, screenshot, and short-demo assets for the live site and public release surfaces.

## Original Request

Use GoalBuddy goal-prep for product story plus screenshots/demo media polish.

## Intake Summary

- Input shape: `specific`
- Audience: prospective Foil users, beta testers, and maintainers preparing the public beta surface
- Authority: `requested`
- Proof type: `artifact`
- Completion proof: The live public surfaces include a coherent Foil product story and at least one verified demo media artifact or screenshot set that demonstrates the core hold-to-record, transcribe, and paste workflow without stale GroqTalk branding.
- Goal oracle: A browser/repo walkthrough proves the landing page, README, release-facing copy, and demo media artifacts consistently explain Foil's value, provider choice, privacy posture, install path, and core workflow.
- Likely misfire: Polishing copy or making attractive assets that do not demonstrate the actual app workflow, do not match the current UI, or leave public surfaces with "demo media has not been published yet" credibility gaps.
- Blind spots considered:
  - Demo capture may require macOS permissions, clean app state, and non-sensitive test content.
  - Assets must not expose API keys, personal data, raw diagnostics, or private desktop content.
  - The abstract Edison-cylinder brand direction is intentionally deferred; this goal should not block on a final hero illustration.
  - Public claims should stay provider-neutral and match current app behavior.
- Existing plan facts:
  - The landing page is live at `https://mean-weasel.github.io/foil/`.
  - The repo homepage points at the landing page.
  - Release `v1.12.1` is titled `Foil 1.12.1`.
  - The next recommended slice was product story plus screenshots/demo media.

## Goal Oracle

The oracle for this goal is:

`A final browser/repo walkthrough can show a coherent public Foil story with verified demo media or screenshots linked from the relevant public surfaces, no stale GroqTalk references in those surfaces, and no unsupported claims about providers, privacy, install, or paste behavior.`

The PM must keep comparing task receipts to this oracle. Planning, discovery, a nice-looking page, or a single screenshot is not enough. The goal finishes only when a final Judge/PM audit maps receipts and verification back to this oracle and records `full_outcome_complete: true`.

## Goal Kind

`specific`

## Current Tranche

This tranche should discover the highest-leverage public storytelling and media gaps, choose the largest safe verified work package, produce or wire in demo/screenshot artifacts, and update public surfaces until the story and media proof are coherent enough for a public beta visitor.

## Non-Negotiable Constraints

- Do not expose API keys, personal transcripts, diagnostics, private desktop content, or local filesystem secrets in media.
- Do not claim capabilities that are not present in the current app.
- Keep the abstract Edison-cylinder hero/brand asset optional and deferred unless the user explicitly reopens that visual direction.
- Preserve provider-neutral language: Groq is supported, local whisper.cpp is supported, and future vendors are possible, but Foil is not Groq-only.
- Prefer real screenshots or demo capture of the app over invented product UI.
- Use the repo's existing release, site, and documentation patterns.
- Keep work reversible and bounded; publish external assets or release edits only with clear receipts.

## Stop Rule

Stop only when a final audit proves the full original outcome is complete.

Do not stop after planning, discovery, or Judge selection if a safe Worker task can be activated.

Do not stop after a single verified Worker package when the broader original outcome still has safe local follow-up work. Advance the board to the next highest-leverage safe Worker package and continue unless a phase, risk, rejected-verification, ambiguity, or final-completion review is due.

Do not stop because a slice needs owner input, credentials, production access, destructive operations, or policy decisions. Mark that exact slice blocked with a receipt, create the smallest safe follow-up or workaround task, and continue all local, non-destructive work that can still move the goal toward the full outcome.

## Slice Sizing

Safe means bounded, explicit, verified, and reversible. It does not mean tiny.

A good task is the largest safe useful slice.

Small is not the goal. Useful is the goal.

A Worker should finish the whole assigned slice. A Judge should judge the whole assigned slice. A PM should reorient the board when tasks are safe but not moving the outcome.

## Canonical Board

Machine truth lives at:

`docs/goals/foil-product-story-demo-media/state.yaml`

If this charter and `state.yaml` disagree, `state.yaml` wins for task status, active task, receipts, verification freshness, and completion truth.

## Run Command

```text
/goal Follow docs/goals/foil-product-story-demo-media/goal.md.
```

## PM Loop

On every `/goal` continuation:

1. Read this charter.
2. Read `state.yaml`.
3. Run the bundled GoalBuddy update checker when available and mention a newer version without blocking.
4. Re-check the intake: original request, input shape, authority, proof, blind spots, existing plan facts, and likely misfire.
5. Work only on the active board task.
6. Assign Scout, Judge, Worker, or PM according to the task.
7. Write a compact task receipt.
8. Update the board.
9. If safe local work remains, choose the next largest reversible Worker package and continue unless blocked.
10. Finish only with a Judge/PM audit receipt that maps receipts and verification back to the original user outcome and records `full_outcome_complete: true`.
