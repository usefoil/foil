## T008 Worker Result

Result: stopped_product_fix_required

Changed `tests/test_queued_paste_compatibility.swift` so the Chrome verifier selects the intended `Foil Queued Chrome Target` window and checks all text controls under that window instead of only the first `AXTextArea` or `AXTextField`.

Verification:

- `swiftc -parse tests/test_queued_paste_compatibility.swift`: pass
- `make prepare-local-permissions-qa-check`: pass with local-signing warnings
- `ALLOW_LOCAL_QA_SKIP=1 make test-queued-paste-compatibility`: failed
- Artifact: `/tmp/foil-queued-paste-compatibility-20260528-081538`

Result details:

- TextEdit queued delivery: pass
- Chrome queued delivery: fail
- Unavailable target fallback: pass

The improved Chrome readback observed the target page controls:

- `/private/var/.../foil-queued-chrome-target.html`
- `Chrome queued target\n`

It did not observe `Mock queued paste automation smoke`, while Foil diagnostics for the same delivery logged `BackgroundPaste: AX insertion succeeded for Google Chrome` and `insertAsync: Tier 1 (AX) verified for Google Chrome`.

Conclusion: the harness is now reading the intended Chrome target. The remaining issue is product behavior: `BackgroundPaste` treats `AXSelectedText` set success as a verified insertion even when Chrome does not mutate the text value. Stop this Worker and open a product-fix slice.
