# T006 Worker Receipt

Result: done

## Summary

Cleaned up setup copy and documentation boundaries.

Changes:

- README setup order now matches the first-run flow: API key, Accessibility, Microphone, setup test.
- Regular troubleshooting copy explains the stale GroqTalk Accessibility row repair path without developer commands.
- Local development docs now contain the `make prepare-local-permissions-qa` and `make prepare-local-permissions-qa-check` commands separately.
- Verified primary app UI source does not expose `make prepare-local-permissions-qa`.

## Verification

Passed:

```text
rg -n "make prepare-local-permissions-qa" GroqTalk/MenuBarView.swift GroqTalk/OnboardingView.swift GroqTalk/SettingsView.swift
```

Result: no matches.

Passed:

```text
rg -n "first-run setup|Add API Key|prepare-local-permissions-qa|prepare-local-permissions-qa-check|old GroqTalk row|Local Permission State Repair" README.md
```

Result: setup order, local repair commands, and user-facing stale-row copy are present in README.
