# UX implementation progress

Scope: implement the September 7 UX audit incrementally. Local transcription is the recommended first-run path; cloud providers remain available with inline credential guidance and official link-outs. Existing provider choices must not be overwritten.

## Sequence

1. Trust: persist history preferences, explicit deletion, truthful delivery feedback, correct shortcut instructions, reliable last-result recovery.
2. Activation: local-first onboarding, guided local setup and cloud keys, microphone and shortcut practice, actual transcript, distinct insertion verification, resumable setup.
3. Everyday UI: actionable Home and provider health, coherent indicators, simple cleanup and clear vocabulary activation, privacy defaults.
4. Local installation: managed runtime/model setup and language-aware recommendations, cancellable/recoverable downloads, truthful readiness.
5. Polish: system appearance, reduced motion, keyboard/accessibility and layout verification.

## Acceptance gates

- History Off and selected limits survive store reconstruction/relaunch; Off writes no new transcript or failed audio; deleting past records is explicit.
- Clipboard fallback and unverified command posting never claim verified delivery. Recovery works with disk history disabled.
- Existing provider preferences survive upgrade. A new user sees local recommended without being told an unavailable model is ready. Cloud users can find official key/billing instructions.
- Completing the tutorial requires a real successful transcript; skipping is labelled as skipping. Transcription and external insertion have separate evidence.
- Live permission, microphone, provider, installation, and cross-app scenarios must be recorded as verified or outstanding; fixture checks are not live proof.

## Evidence

Implementation and validation receipts will be recorded here by stage. No release or installation into the production app is implied.

### First implementation tranche: trust and guided activation

Implemented on `codex/ux-onboarding-improvements`:

- History preferences persist in an atomic sidecar file. Corrupt preferences fail closed; write errors are visible in Settings. Off stops new storage and no longer deletes old records. Clear History is explicit. Last-result recovery works in memory with storage off.
- Unverified paste commands and clipboard fallback have distinct presentation. Default feedback uses the compact active indicator, with a separate opt-in idle indicator and detailed feedback. Recovery is shown regardless of the routine feedback preference.
- Home follows the actual shortcut and hold/toggle mode, collapses healthy permission details, gives transcripts full width, and provides Copy last result, per-transcript Copy, and a setup/practice entry point.
- First-run setup recommends local without overriding an existing provider. Local setup has model/language guidance, copyable installation commands, Start, and Test connection. Cloud setup has inline Save & Test and official key-management/quickstart links.
- Setup requires a practice transcript before completion. Practice results bypass History and automatic paste. External insertion is a separate user-confirmed check that can remain explicitly unconfirmed. Setup can be deferred and resumed without persisting practice text.

Validation so far:

- `/tmp/foil-ux-history-tests.xcresult`: 55 history tests passed, including Off/retention reconstruction, corrupt settings, explicit deletion, and memory-only recovery.
- `/tmp/foil-ux-trust-tests.xcresult`: 225 focused tests passed.
- `/tmp/foil-ux-all-unit-tests-v2.xcresult`: 704 XCTest tests and 9 Swift Testing tests passed. An initial migration test failed because AppState initialization itself writes the legacy provider value; the implementation now captures whether a provider was configured before those initialization writes, and the regression test passes.
- An intermediate test run stalled on a macOS Keychain interaction. It was stopped without granting access; subsequent tests used the repository's stable Developer ID signing identity and passed.
- `/tmp/foil-ux-validation-v3.xcresult`: 706 XCTest unit tests and 9 Swift Testing tests passed, plus four focused UI tests. The earlier focused UI run passed ten of twelve scenarios; its two Home failures exposed inaccessible child identifiers. Adding an accessibility containment boundary fixed both, verified in this final run. Across these runs, all twelve selected UI scenarios have passed.
- `/tmp/foil-ux-warning-clean-build.log`: FoilDev build passed with `OTHER_SWIFT_FLAGS='-warnings-as-errors'` and stable Developer ID signing.
- Recompiled the original audit probe against the changed history model: `After Off and reconstruction: enabled=false, records=0, fileExists=false`; `After choosing 100 and reconstruction: retention=100`.
- Visually inspected the passing UI-test captures: [Home](../evidence/ux-onboarding/home.png), [local setup](../evidence/ux-onboarding/local-setup.png), and [cloud setup](../evidence/ux-onboarding/cloud-setup.png). These contain seeded test data. Text and controls fit the captured window sizes; this does not establish all accessibility sizes or appearances.

Failure-mode checks:

| Claim | Strong realistic failure mode | Evidence and limits |
| --- | --- | --- |
| History Off persists | A new store silently resumes writing private transcripts | Reconstruction tests and independently compiled original audit probe confirm Off survives; corrupt preferences fail closed. |
| Local is the first-run recommendation | Initialization writes make a new account appear previously configured | Regression test captures configuration before initialization writes; existing provider selections are separately preserved. |
| Setup requires a transcript | Next/Finish enables from permissions or a mock alone | UI completion gating plus controller tests: practice ignores the mock flag, invokes transport, skips cleanup/metrics, and deletes cancelled audio. Fixture transcripts are not live microphone proof. |
| Feedback distinguishes delivery confidence | Posted commands appear as verified insertion | Delivery/AppState tests exercise unverified and clipboard presentation. Actual cross-app insertion remains unverified. |
| Controls remain usable | Parent accessibility identifiers hide Home children | Initial UI failures reproduced this; containment fix and reruns pass. Screenshots verify the tested layouts. |

Live microphone/provider and cross-app scenarios were not run in this tranche; deterministic transport and UI fixtures avoid using personal audio, credentials, or target documents. These remain acceptance work for the subsequent implementation stages, before release. No production installation was performed.

Remaining stages (not claimed implemented or validated):

- App-managed runtime/model installation with verified downloads, cancellation/resume, packaging/signing, and offline relaunch proof. Current local setup still needs the explicitly documented one-time commands.
- Provider health beyond permissions/credentials; safe focus-change delivery and destination confirmation; cross-app compatibility proof.
- Cleanup/vocabulary restructuring, privacy default changes, system appearance, reduced motion, and a full accessibility review.
- Live fresh-user permission, microphone, cloud, local model, and external insertion acceptance runs. No release readiness claim is made from deterministic tests alone.
