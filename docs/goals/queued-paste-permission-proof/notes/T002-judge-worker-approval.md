# T002 Judge: Worker Approval

## Decision

approved

## Rationale

The largest safe useful slice is one Worker package that prepares the signed installed app, opens the guided permission path, waits for operator consent refresh, reruns the queued compatibility smoke, and records the outcome. Splitting this into smaller tasks would risk validating signing while never reaching the actual oracle: TextEdit/Chrome queued delivery under the corrected installed-app identity.

The slice is safe because product-code edits are out of scope unless the refreshed-consent smoke proves Foil is trusted and queued delivery still fails. It also preserves the Chrome safety constraint because the existing smoke wrapper explicitly says it must not quit the user's browser, and PR 161 removed the previous unsafe Chrome cleanup behavior.

## Approved Worker Objective

Execute the full post-PR161 local package:

1. Repair/use local signing.
2. Install `/Applications/Foil.app` with `Foil Local Code Signing`.
3. Verify installed app identity.
4. Open guided privacy panes for operator refresh.
5. After operator confirms Accessibility/Input Monitoring refresh and Foil restart, run the queued-paste compatibility smoke.
6. Record artifact path, diagnostics, and outcome.

## Allowed Files

- `docs/queued-paste-compatibility-smoke.md`
- `docs/release-qa-log.md`
- `docs/goals/queued-paste-permission-proof/state.yaml`
- `docs/goals/queued-paste-permission-proof/notes/*`

## Verify

- `make setup-local-signing LOCAL_SIGN_KEYCHAIN_PASSWORD=foil-local-codesign`
- `make install SIGN_IDENTITY="Foil Local Code Signing" LOCAL_SIGN_KEYCHAIN_PASSWORD=foil-local-codesign`
- `make prepare-local-permissions-qa-check`
- `make guide-installed-permissions-qa`
- Operator refreshes Accessibility/Input Monitoring for `/Applications/Foil.app`, then quits/reopens Foil.
- `ALLOW_LOCAL_QA_SKIP=1 make test-queued-paste-compatibility`
- `tail ~/Library/Application\ Support/Foil/Diagnostics/foil.log`
- `git diff --check`
- GoalBuddy state checker

## Branching Rule

- If TextEdit, Chrome, and unavailable-target fallback pass, record evidence and activate T004 for evidence-completion classification.
- If Foil diagnostics show `SetupHealth: accessibilityTrusted=true` but TextEdit or Chrome delivery fails, stop product edits and activate T004 for product-fix scoping.
- If Foil diagnostics still show `SetupHealth: accessibilityTrusted=false`, record operator-consent blocker evidence and activate T004 for blocked-handoff classification.

## Stop Conditions

- The operator has not completed macOS privacy consent refresh.
- The smoke would quit Chrome or close the active Chrome tab.
- Product-code edits are needed before Judge expands scope.
- Verification fails twice with the same unexplained failure.
