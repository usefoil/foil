# T003 Worker Partial: Permission Boundary

## Status

in_progress

## Completed

Commands run:

```sh
make setup-local-signing LOCAL_SIGN_KEYCHAIN_PASSWORD=foil-local-codesign
make install SIGN_IDENTITY="Foil Local Code Signing" LOCAL_SIGN_KEYCHAIN_PASSWORD=foil-local-codesign
make prepare-local-permissions-qa-check
make guide-installed-permissions-qa
```

Results:

- Local signing identity exists and `setup-local-signing` completed.
- Signed Debug install to `/Applications/Foil.app` succeeded.
- `make prepare-local-permissions-qa-check` passed with one expected local-signing warning for missing team id.
- `make guide-installed-permissions-qa` launched Foil and opened the macOS Privacy & Security panes.

## Current Boundary

Foil diagnostics still show:

```text
SetupHealth: accessibilityTrusted=false
```

## Latest Recheck

After resuming the goal, `make prepare-local-permissions-qa-check` passed again
with the installed app running from `/Applications/Foil.app`, but diagnostics
still ended with:

```text
SetupHealth: accessibilityTrusted=false
```

This confirms the signing/app-identity portion is still good, and the remaining
boundary is manual Accessibility/Input Monitoring consent for that installed app
identity.

## Blocked Audit

A further goal continuation repeated the same evidence:

- `make prepare-local-permissions-qa-check` passes.
- Foil is running from `/Applications/Foil.app`.
- The installed app identity remains `com.neonwatty.Foil` signed by `Foil Local Code Signing`.
- Foil diagnostics still show `SetupHealth: accessibilityTrusted=false`.

This is the third consecutive goal turn with the same blocker. The Worker cannot
validly run `ALLOW_LOCAL_QA_SKIP=1 make test-queued-paste-compatibility` until
macOS Accessibility/Input Monitoring consent is refreshed for the installed app
identity.

## Resume Attempt

The operator reported the consent refresh was done, but the next check still did
not satisfy the resume condition:

- `make prepare-local-permissions-qa-check` passed.
- Foil was running from `/Applications/Foil.app`.
- The log showed a fresh launch at `2026-05-28T15:02:52Z`.
- That fresh launch still reported `SetupHealth: accessibilityTrusted=false`.

`make guide-installed-permissions-qa` was run again to reopen the exact privacy
panes for the installed app identity. The next attempt should remove any stale
Foil rows from Accessibility, add `/Applications/Foil.app` explicitly if needed,
then quit and reopen Foil.

## App-Scoped TCC Reset

The visible Accessibility row was enabled, but Foil still reported
`accessibilityTrusted=false` after restart. To clear a likely stale code
requirement row, the local permissions helper was run in default mode:

```sh
MAKE_CMD=make SIGN_IDENTITY="Foil Local Code Signing" LOCAL_SIGN_KEYCHAIN_PASSWORD=foil-local-codesign scripts/prepare-local-permissions-qa.sh
```

This rebuilt and reinstalled `/Applications/Foil.app`, verified the signing
identity, reset only the `com.neonwatty.Foil` Accessibility and ListenEvent TCC
records, relaunched Foil, and reopened the privacy panes. It did not grant
consent. Diagnostics still show `SetupHealth: accessibilityTrusted=false` until
the operator enables the new Foil row and restarts the app.

The next required step is operator action in macOS System Settings:

1. In Accessibility, remove/re-add or toggle Foil off/on.
2. In Input Monitoring, remove/re-add or toggle Foil off/on if Foil appears.
3. Quit and reopen `/Applications/Foil.app`.
4. Confirm diagnostics show `SetupHealth: accessibilityTrusted=true`.

Do not run `ALLOW_LOCAL_QA_SKIP=1 make test-queued-paste-compatibility` until the installed app reports Accessibility trust.
