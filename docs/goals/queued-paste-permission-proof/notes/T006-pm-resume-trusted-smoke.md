## T006 PM Resume Result

Result: done

The operator refreshed macOS Accessibility for `/Applications/Foil.app` and a fresh Foil launch logged `SetupHealth: accessibilityTrusted=true`. The installed-app identity precheck still passed for bundle identifier `com.neonwatty.Foil` and signing authority `Foil Local Code Signing`.

Verification run:

- `make prepare-local-permissions-qa-check`: pass
- `ALLOW_LOCAL_QA_SKIP=1 make test-queued-paste-compatibility`: failed
- Artifact: `/tmp/foil-queued-paste-compatibility-20260528-081109`

Smoke result:

- TextEdit queued delivery: pass
- Unavailable target fallback: pass
- Chrome queued delivery: reported fail

Foil diagnostics for the Chrome segment show the app captured a Google Chrome `PasteTarget`, executed `PasteController.pasteQueued`, completed `BackgroundPaste: AX insertion succeeded for Google Chrome`, verified Tier 1 AX insertion, and logged `QueuedPaste.deliver: ... delivery=original app`. The failing signal is therefore the smoke verifier's Chrome readback, not current evidence of product delivery failure.

Next decision: classify this as a bounded compatibility-smoke harness fix before considering any product code changes.
