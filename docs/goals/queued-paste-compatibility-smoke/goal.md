# Queued Paste Compatibility Smoke

## Original Request

Continue after the merged queued-paste MVP by planning the next steps with GoalBuddy before starting implementation.

## Interpreted Outcome

Prepare and execute the next safe tranche for issue 159: validate queued paste against representative real paste targets, record the compatibility matrix, and identify any product fixes needed before adding a global queue delivery hotkey or overlapping recording/transcription support.

## Goal Kind

specific

## Current Tranche

Build confidence that the PR1 queued-paste MVP correctly records and uses the original target app/window identity in realistic paste targets. This tranche should produce a source-controlled smoke matrix and, if needed, bounded follow-up implementation tasks for discovered compatibility gaps.

## Oracle

The tranche is complete when a final Judge or PM audit maps receipts to:

- At least TextEdit and one browser text-entry target covered by a manual or automated queued-paste smoke.
- Smoke evidence records whether queued paste returns to the intended app/window, not just a screen location.
- Failed or unavailable target fallback behavior is exercised or explicitly documented.
- A repo-native compatibility matrix or runbook is added or updated.
- Any app-specific limitations or product defects are captured as follow-up tasks or issues.
- No global queued-paste delivery hotkey is added.
- No overlapping recording/transcription architecture is added.

## Non-Goals

- Do not add a global queued-paste hotkey in this tranche.
- Do not restructure Foil for overlapping recordings or overlapping transcription jobs.
- Do not broaden into release packaging or distribution work unless a smoke result proves it is blocking this tranche.
- Do not treat the existing unit/UI tests alone as sufficient; this tranche is about real-target compatibility evidence.

## Likely Misfire

Stopping after a written plan, or adding more automated internals while failing to prove queued paste works against real target applications where users actually paste.

## Blind Spots To Audit

- Some apps may expose weak or changing Accessibility window identity.
- Browser text fields may behave differently by browser and focus state.
- Queue delivery may succeed by clipboard fallback while not actually returning to the intended target app/window.
- Manual smoke steps can become vague unless the matrix records target app, target field/window, expected behavior, observed result, and artifact or command evidence.

## Starter Command

```text
/goal Follow docs/goals/queued-paste-compatibility-smoke/goal.md.
```
