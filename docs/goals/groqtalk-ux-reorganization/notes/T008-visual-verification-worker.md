# T008 Worker Receipt

Result: done

## Summary

Captured visual receipts without running `make test-ui` or XCUITest.

Method:

- Built app was launched with existing `--ui-testing` seed flags.
- Screenshots were captured from real macOS windows using `screencapture -l`.
- GroqTalk was stopped after the capture flow to avoid duplicate menu bar instances.

## Artifacts

- `docs/goals/groqtalk-ux-reorganization/notes/visual/ready-menu-host.png`
- `docs/goals/groqtalk-ux-reorganization/notes/visual/setup-needed-menu-host.png`
- `docs/goals/groqtalk-ux-reorganization/notes/visual/onboarding-setup.png`
- `docs/goals/groqtalk-ux-reorganization/notes/visual/settings-transcription.png`

## Visual Findings

- Ready menu shows the lean control center: toolbar, session hero, record controls, and compact last result; no setup checklist or durable quick controls.
- Setup-needed menu shows session hero plus detailed setup rows and local setup test.
- Onboarding setup shows the Groq API Key step with Add API Key action.
- Settings Transcription pane shows provider first, credentials second, model/speech language below.

## Verification

Passed:

```text
pgrep -x GroqTalk || true
```

Result after capture flow: no running GroqTalk process.
