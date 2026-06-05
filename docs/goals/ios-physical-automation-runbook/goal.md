# Foil iOS Physical Automation Runbook

## Intent

Make physical iPhone testing repeatable enough that future GoalBuddy boards can restore WDA/tunnel state, verify device reachability, run safe target-app probes, and stop with exact blockers instead of rediscovering the same setup every time.

## Oracle

The goal is complete when the repo contains a small, reviewed runbook or helper surface for Foil iOS physical automation, backed by a smoke test against the current machine/device state or a precise blocker. The proof must avoid private app content and must include commands, expected output shape, cleanup instructions, and how to tell when WDA/device/tunnel state is usable.

## Starting Facts

- PR #229 landed the iOS TestFlight onboarding/recovery slice.
- PR #230 landed archive/export metadata proof.
- Prior physical testing used iPhone-preview, WDA/Appium WebDriverAgent, local `curl` checks, sterile Safari fixtures, and direct `xcodebuild` WDA commands.
- WDA is often down between runs; device state and tunnel reachability need fast diagnosis.
- Messages remains out of scope unless a safe self/test thread exists.

## Non-Goals

- Do not automate private Messages content.
- Do not commit raw accessibility trees, screenshots with private data, API keys, transcript bodies, or device-specific secrets.
- Do not require installing new global packages unless Scout/Judge proves they are already absent and necessary.
- Do not change app product behavior unless Judge explicitly expands the scope.

## Starter Command

`/goal Follow docs/goals/ios-physical-automation-runbook/goal.md.`
