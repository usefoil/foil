# Local whisper.cpp Model Setup Helper

## Objective

Create a user-facing Local whisper.cpp model setup helper for Foil that lets installed-app users choose an actually available whisper.cpp model option, understand the speed/quality tradeoff, copy deterministic install/download/start commands, test the local server, and avoid confusing the OpenAI-compatible `model=whisper-1` request field with the real local `--model` file.

## Original Request

"Make a GoalBuddy plan for the local model setup helper and make sure all of the models are actually available."

## Intake Summary

- Input shape: `existing_plan`
- Audience: Foil installed-app users who want local transcription, plus maintainers who need CI-safe coverage.
- Authority: `requested`
- Proof type: `source_backed_answer` plus `test`
- Completion proof: A final audit maps source-backed model availability evidence, implemented in-app setup helper UI, docs, and passing focused tests back to the original user outcome.
- Goal oracle: The setup helper is complete only when every model option shown in Foil is backed by current whisper.cpp availability evidence, the app generates correct copyable commands for those options, CI-safe tests cover the helper, and docs explain the model-file-vs-API-model distinction.
- Likely misfire: Building a polished model picker around guessed model names, stale model names, or app-side `whisper-1` semantics instead of verifying real whisper.cpp model download/support names.
- Blind spots considered:
  - `whisper.cpp` model script names and supported server flags may change over time.
  - The app currently uses a fixed Local whisper.cpp preset; the helper should generate setup commands first, not silently change transcription behavior.
  - Downloading/building/running whisper.cpp inside the app adds permissions, bandwidth, architecture, and process-supervision risk.
  - Regular CI should remain free of model downloads, network server requirements, and vendored model files.
  - English-only and multilingual model names may differ in availability and user expectations.
- Existing plan facts:
  - Current Local whisper.cpp preset uses `http://127.0.0.1:8080/v1`, `model=whisper-1`, optional API key, and no transcript cleanup.
  - The real local model is chosen by the `whisper-server --model /path/to/ggml-*.bin` file.
  - Existing docs show `tiny.en` as an example and an opt-in live E2E harness.
  - Proposed first product slice is an in-app setup helper with model guidance and copyable commands, not a full downloader/manager.

## Goal Oracle

The oracle for this goal is:

`A fresh maintainer can run the board's verification commands and see that the app only lists source-verified whisper.cpp model options, generates correct setup/download/start commands for each option, shows the setup helper when Local whisper.cpp is selected, and preserves a deterministic CI-safe provider QA path without downloading models.`

The PM must keep comparing task receipts to this oracle. Planning, guessed model lists, docs-only changes, or tests that do not cover the actual helper are not enough.

## Goal Kind

`existing_plan`

## Current Tranche

Deliver the smallest useful implementation tranche for Local whisper.cpp model setup: source-verify available model names, add a command-generation model, expose a compact in-app helper with copyable commands, update docs, and add CI-safe tests. Do not build a full installer, model downloader, background server supervisor, or bundled model distribution in this tranche.

## Non-Negotiable Constraints

- Do not list a model option in the app unless a Scout receipt cites current source evidence that the model is available through whisper.cpp or a supported ggml model path.
- Do not vendor whisper.cpp source or model files into this repo.
- Do not make regular CI download models or start a live local server.
- Do not imply that changing the app's `model=whisper-1` field selects the real whisper.cpp model file.
- Preserve the existing Local whisper.cpp preset behavior unless a Judge explicitly approves a larger behavior change.
- Keep commands copyable, deterministic, and macOS-oriented.
- Keep user-facing setup guidance concise enough for Settings, with deeper details in docs.

## Stop Rule

Stop only when a final audit proves the current tranche satisfies the oracle.

Do not stop after verifying model availability if there is a safe Worker task for the helper. Do not stop after adding UI if docs or tests are still required.

## Slice Sizing

Use the largest safe useful slices:

1. Scout actual current whisper.cpp model availability and command semantics from source-backed references.
2. Judge the verified model list and exact first implementation package.
3. Implement command-generation data/model plus unit tests.
4. Implement the in-app helper and CI-safe UI coverage.
5. Update docs and optional developer discoverability.
6. Final audit against the oracle.

## Canonical Board

Machine truth lives at:

`docs/goals/local-whisper-model-setup-helper/state.yaml`

If this charter and `state.yaml` disagree, `state.yaml` wins for task status, active task, receipts, verification freshness, and completion truth.

## Run Command

```text
/goal Follow docs/goals/local-whisper-model-setup-helper/goal.md.
```

