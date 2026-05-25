# Foil UX Workflow Clarity

## Objective

Improve Foil's first-run and daily-use UX so the app clearly communicates the core loop: hold a hotkey, speak, send to Groq, paste into the intended app, and recover cleanly when setup or paste delivery needs attention.

## Original Request

Create a concrete GoalBuddy-ready list of Foil UX, styling, and native macOS improvements with clear acceptance criteria. Prioritize core workflow clarity first, while preparing detailed follow-up plans for visual distinctiveness and native macOS polish.

## Intake Summary

- Input shape: `existing_plan`
- Audience: Foil users installing and using the macOS menu bar app.
- Authority: `approved`
- Proof type: `test`, `demo`, `artifact`, `review`
- Completion proof: Tranche 1 is complete when implemented UX changes pass build/tests, key flows are visually checked in the running app with screenshots or equivalent demo notes, and final audit maps the result back to the acceptance criteria below. Tranche 2 and 3 follow-up plans must be detailed enough to start after tranche 1 without rediscovery.
- Likely misfire: GoalBuddy could produce a broad redesign or styling polish while leaving first-run setup, paste confidence, recovery actions, and daily-use status clarity unresolved.
- Blind spots considered: Scope creep into a full brand overhaul, insufficient visual proof for UX work, duplicated settings surfaces, accessibility/dynamic type issues, and accidentally burying the product premise behind technical controls.
- Existing plan facts:
  - First tranche optimizes for core workflow clarity.
  - Detailed plans must also be prepared for visual distinctiveness and native macOS polish.
  - Completion proof must include working code verification plus visual/manual evidence.
  - First tranche excludes asset or brand overhaul; light UI changes are allowed only when they directly support workflow clarity.
  - Local live GoalBuddy board was requested.

## Goal Kind

`existing_plan`

## Current Tranche

Execute tranche 1: core workflow clarity. Discover only enough current-state evidence to validate the plan, then implement successive safe verified slices until the first-run and daily-use voice workflow is materially clearer. Preserve tranche 2 and 3 as detailed follow-up plans, not implementation work, unless tranche 1 final audit proves complete and the board advances.

### Tranche 1: Core Workflow Clarity

Acceptance criteria:

- First-run onboarding has a complete, actionable path:
  - Users can add or open the API key setup from onboarding.
  - Users can request or verify microphone permission from onboarding.
  - Accessibility and microphone steps provide contextual recovery copy and a way to re-check readiness.
  - Users are not left at a disabled final button without a clear next action.
  - The payoff is explicit: hold the chosen hotkey, speak, release/stop, and text appears in the target app.

- The menu bar default panel emphasizes the voice workflow:
  - The primary visible area is a clear session/status surface, not an admin-style stack of equal panels.
  - Ready, recording, transcribing, cleaning, pasting, delivered, clipboard fallback, setup-needed, and error states use user-facing copy.
  - Low-frequency toggles are reduced, relocated, or grouped so they do not dominate the default control view.
  - Setup health remains discoverable without crowding the normal ready state.

- Paste confidence is surfaced as outcome, not as only technical settings:
  - The UI can communicate the intended target when known.
  - Delivery result distinguishes successful paste, command-posted/uncertain paste if applicable, and clipboard fallback.
  - Recovery paths for fallback or blocked paste point to copy/paste-again/history actions.
  - Copy avoids overpromising verification where the app cannot prove the target accepted the paste.

- The floating HUD supports the same workflow language:
  - HUD states align with menu status language.
  - HUD exposes or routes to the right recovery actions for setup and retryable errors.
  - Active recording/transcription remains compact and non-disruptive.
  - HUD styling changes are limited to clarity and consistency, not a brand overhaul.

- History and recovery flows become clearer:
  - Copy/export actions are accurately labeled and/or provide confirmation.
  - Retryable failures and fallback cases are visually and textually easy to distinguish.
  - No-audio or too-short recording outcomes provide user-facing feedback instead of silently returning to idle.
  - Last transcript actions support the core loop: copy, paste again, retry when available, open details/history when needed.

- Verification for tranche 1:
  - Relevant unit/UI tests pass or are updated to cover the changed behavior.
  - The app builds successfully.
  - A manual/demo pass captures evidence for onboarding, ready/recording/transcribing/pasting/fallback/error states where locally feasible.
  - Final Judge/PM audit confirms full tranche 1 completion against this charter and records any remaining risk.

### Tranche 2: Visual Distinctiveness Plan

Prepare but do not implement during tranche 1 unless explicitly advanced after audit.

Planned acceptance criteria:

- Define a small Foil visual signature that supports speed, voice, and paste confidence without becoming a marketing-style redesign.
- Unify the menu status strip and floating HUD around one reusable voice-status surface.
- Establish a restrained accent system: semantic colors remain for status, one stable brand accent supports idle/ready and non-alert UI.
- Standardize icon mapping for API key, microphone, Accessibility, transcription, cleanup, paste, fallback, retry, and history.
- Improve onboarding and API key setup visual motifs with workflow-specific elements such as waveform/progress/transcript preview/hotkey affordance, not new external assets unless explicitly approved.
- Identify limited motion opportunities for recording, transcribing, success, and fallback states with accessibility-safe reduced-motion behavior.
- Produce screenshots or mockups before broad visual implementation.

### Tranche 3: Native macOS Polish Plan

Prepare but do not implement during tranche 1 unless explicitly advanced after audit.

Planned acceptance criteria:

- Add or improve native macOS commands for Settings/Preferences, History, Start/Stop/Cancel recording, Help/Troubleshooting, Copy/Paste Again, and Delete where appropriate.
- Make Settings reachability consistent: embedded quick settings should either link clearly to full Settings or avoid implying advanced settings do not exist.
- Replace color-only panel selection with segmented selection or explicit selected accessibility traits.
- Make history more native with keyboard navigation, selection, context menus, delete behavior, and search/filter affordances.
- Convert custom hotkey recording into a focusable keyboard-accessible control with clear active/cancel states.
- Reduce fixed-size clipping risk for Settings, onboarding, API key setup, floating HUD, and menu popover.
- Review permission prompting timing so system prompts occur with user context.
- Verify VoiceOver labels, keyboard paths, dynamic text behavior, and Light/Dark mode for touched surfaces.

## Non-Negotiable Constraints

- Do not perform a full asset or brand overhaul in tranche 1.
- Keep changes native to macOS and aligned with SwiftUI/AppKit conventions.
- Preserve the LSUIElement/menu-bar app model.
- Preserve user privacy guarantees: API keys in Keychain, local history, no unnecessary transcript logging.
- Avoid private API expansion; background paste remains experimental and must not be presented as guaranteed.
- Do not remove advanced controls without preserving a discoverable path to them.
- Use verified behavior and screenshots/manual notes for UX completion, not only subjective impressions.

## Stop Rule

Stop only when a final audit proves the full original outcome for the current tranche is complete.

Do not stop after planning, discovery, or Judge selection if safe Worker work can proceed.

Do not stop after a single verified Worker package when tranche 1 still has safe local follow-up work. Advance the board to the next highest-leverage safe Worker package and continue unless a phase, risk, rejected-verification, ambiguity, or final-completion review is due.

Do not implement tranche 2 or 3 before tranche 1 final audit unless the board is explicitly advanced.

## Slice Sizing

Safe means bounded, explicit, verified, and reversible. It does not mean tiny.

A good Worker slice for this goal should complete a coherent user-facing flow: onboarding setup completion, menu/HUD status language, paste confidence and recovery, history/retry clarity, or verification/demo capture.

Avoid one Worker per label or per button unless a tiny isolated task is needed to unblock a larger slice.

## Canonical Board

Machine truth lives at:

`docs/goals/foil-ux-workflow-clarity/state.yaml`

If this charter and `state.yaml` disagree, `state.yaml` wins for task status, active task, receipts, verification freshness, and completion truth.

## Run Command

```text
/goal Follow docs/goals/foil-ux-workflow-clarity/goal.md.
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
9. Continue with the next largest safe Worker package until tranche 1 acceptance criteria are satisfied and follow-up plans for tranche 2/3 are preserved.
10. Finish only with a Judge/PM audit receipt that maps receipts and verification back to the original user outcome and records `full_outcome_complete: true`.
