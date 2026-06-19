# Transcript Cleanup Formatting Autonomous Handoff

## Objective

Implement the approved transcript cleanup formatting feature so Foil can
optionally send completed speech-to-text transcripts through an independently
configured LLM cleanup provider, paste the cleaned result, and fall back to raw
text with a warning when cleanup fails.

## Original Request

"Prepare this plan to hand off to the MacBook Air agent so it can run
autonomously with as little blocking and manual input as possible."

## Source Spec

The approved design spec is:

`docs/superpowers/specs/2026-06-19-transcript-cleanup-formatting-design.md`

## Intake Summary

- Input shape: `existing_plan`
- Audience: the MacBook Air Codex agent implementing the feature and the Foil
  maintainer reviewing the resulting PR.
- Authority: `requested`
- Proof type: `test`
- Completion proof: a final audit maps completed receipts to the approved spec,
  passing focused unit/UI tests, diagnostic redaction proof, and a PR-ready
  branch.
- Goal oracle: a fresh checkout can run the targeted verification bundle and
  prove cleanup routing, prompt assembly, glossary handling, fallback behavior,
  history storage, diagnostics redaction, and Settings UI behavior.
- Likely misfire: the agent only adds a prompt field or UI toggle while leaving
  provider routing, privacy copy, fallback behavior, or tests ambiguous.
- Blind spots considered:
  - `docs/goals/` is currently ignored in this worktree, so publishing this
    handoff requires explicit staging or a different plan location.
  - Cleanup text is sensitive; diagnostics must not leak transcripts, custom
    prompts, preferred terms, or API keys.
  - The speech-to-text provider and cleanup provider must remain independently
    configurable.
  - The existing `rewriteClearly` mode should not become the main UI surface for
    this v1 cleanup-formatting pass.
  - The remote agent may not have API keys or live providers; local mocked
    tests must carry most proof.

## Goal Oracle

The oracle for this goal is:

`A fresh checkout can run focused tests proving transcript cleanup formatting is optional, independently routed from STT, prompt/glossary-aware, raw-fallback-safe, history-minimal, diagnostically redacted, and visible in Settings only when enabled.`

The PM must keep comparing task receipts to this oracle. Planning, discovery,
or a passing narrow unit test is not enough.

## Goal Kind

`existing_plan`

## Current Tranche

Turn the approved design spec into PR-ready implementation work with an
autonomous GoalBuddy board and an implementation plan suitable for another
Codex agent to execute on the MacBook Air.

## Non-Negotiable Constraints

- Preserve the existing speech-to-text provider abstraction.
- Keep cleanup provider configuration independent from transcription provider
  configuration.
- Cleanup must be opt-in and non-blocking.
- If speech-to-text succeeds and cleanup fails, paste/store the raw transcript
  as the final text and surface a warning.
- History stores only the final pasted text.
- Do not log transcript text, cleaned text, custom prompt text, preferred terms,
  API keys, or bearer tokens.
- Prefer local mocked tests over live provider dependencies.
- Do not remove or revert unrelated working-tree changes.

## Canonical Board

Machine truth lives at:

`docs/goals/transcript-cleanup-formatting-handoff/state.yaml`

If this charter and `state.yaml` disagree, `state.yaml` wins for task status,
active task, receipts, verification freshness, and completion truth.

## Run Command

```text
/goal Follow docs/goals/transcript-cleanup-formatting-handoff/goal.md.
```

## PM Loop

On every `/goal` continuation:

1. Read this charter.
2. Read `state.yaml`.
3. Read the approved design spec.
4. Re-check the likely misfire: prompt-only changes are not enough.
5. Work only on the active board task.
6. Write a compact task receipt.
7. Update the board.
8. Continue until the oracle is satisfied or a specific task is blocked with a
   receipt.
