# T001 Scout: Permission And Smoke Rerun Path

## Summary

PR 161 is merged into `main` as `5f901f5e59348cd45ada3b6a0e472d010c7c32b7`. The local signing/keychain blocker is resolved in source: `scripts/setup-local-signing.sh` now unlocks `foil-codesign` and re-applies the `apple-tool:,apple:,codesign:` partition list for existing identities.

The remaining proof is not another signing repair. It is a macOS privacy-consent proof for the newly signed `/Applications/Foil.app` identity, followed by the existing queued-paste compatibility smoke.

## Confirmed Command Sequence

Use this sequence for the Worker slice:

```sh
make setup-local-signing LOCAL_SIGN_KEYCHAIN_PASSWORD=foil-local-codesign
make install SIGN_IDENTITY="Foil Local Code Signing" LOCAL_SIGN_KEYCHAIN_PASSWORD=foil-local-codesign
make prepare-local-permissions-qa-check
make guide-installed-permissions-qa
```

Then the operator must refresh macOS consent manually:

1. In Accessibility, remove/re-add or toggle Foil off/on.
2. In Input Monitoring, do the same if Foil appears.
3. Quit and reopen Foil.
4. Confirm diagnostics from `/Applications/Foil.app` report `SetupHealth: accessibilityTrusted=true`.

Then run:

```sh
ALLOW_LOCAL_QA_SKIP=1 make test-queued-paste-compatibility
```

## Evidence That Consent Is Refreshed

Strong evidence:

- `make prepare-local-permissions-qa-check` passes and shows `codesign identifier matches bundle id: com.neonwatty.Foil`.
- Foil diagnostics show `SetupHealth: accessibilityTrusted=true` after launching `/Applications/Foil.app`.
- The installed app process path is `/Applications/Foil.app/Contents/MacOS/Foil`, not a DerivedData/debug path.

Weak evidence:

- Merely seeing Foil listed in System Settings.
- Passing `make prepare-local-permissions-qa-check` alone.
- Passing cross-app helper tests that run from Swift scripts rather than the installed app.

## Outcome Branches

Pass branch:

- `ALLOW_LOCAL_QA_SKIP=1 make test-queued-paste-compatibility` exits 0.
- TextEdit queued delivery passes.
- Chrome queued delivery passes.
- Unavailable-target fallback passes.
- Update `docs/queued-paste-compatibility-smoke.md` and `docs/release-qa-log.md` with artifact path and current result.

Trusted-app failure branch:

- Foil diagnostics show `SetupHealth: accessibilityTrusted=true`.
- TextEdit or Chrome queued delivery still fails.
- Stop before product edits and route through Judge for a bounded product-fix Worker.

Operator-consent blocker branch:

- Signing identity is clean, but diagnostics still show `SetupHealth: accessibilityTrusted=false`.
- Record that macOS consent still needs operator action; do not call the goal complete.

## Candidate Worker Slice

Objective:

Execute the full local permission-refresh and queued-smoke rerun package, record the outcome, and branch according to pass, trusted-app failure, or operator-consent blocker.

Allowed files:

- `docs/queued-paste-compatibility-smoke.md`
- `docs/release-qa-log.md`
- `docs/goals/queued-paste-permission-proof/state.yaml`
- `docs/goals/queued-paste-permission-proof/notes/*`

Verify:

- `make setup-local-signing LOCAL_SIGN_KEYCHAIN_PASSWORD=foil-local-codesign`
- `make install SIGN_IDENTITY="Foil Local Code Signing" LOCAL_SIGN_KEYCHAIN_PASSWORD=foil-local-codesign`
- `make prepare-local-permissions-qa-check`
- `make guide-installed-permissions-qa`
- Operator refresh of Accessibility/Input Monitoring for `/Applications/Foil.app`
- `ALLOW_LOCAL_QA_SKIP=1 make test-queued-paste-compatibility`
- `tail ~/Library/Application\ Support/Foil/Diagnostics/foil.log`
- `git diff --check`
- GoalBuddy state checker

Stop if:

- The operator has not completed macOS privacy consent refresh.
- The smoke would quit Chrome or close the active Chrome tab.
- Foil is trusted but TextEdit/Chrome queued delivery still fails, requiring product-code scope expansion.
- Product edits are needed before Judge approves allowed files.
