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

### Managed local GUI (T004, issue #397)

The effective transcription choice now distinguishes Foil-managed local models
from the preserved legacy provider preset. First-run recommendation selects managed
intent without downloading or rewriting an existing provider. Onboarding, Transcription
Settings, and Home share that effective choice and owned-session readiness. Explicit
cloud, custom, or advanced external selection cancels pending managed work.

Managed setup asks English-only versus other/multiple languages, recommends only the
pinned Base English or Base Multilingual catalog entry, and shows exact catalog download/
installed size plus separate temporary installation headroom. It drives the production
coordinator for install, switch, cancel, retry, restore, connection testing, and eligible
inactive removal. UI status separates installed, selected, active, and candidate identity;
download progress uses received bytes while verification/startup remain indeterminate.
External whisper.cpp commands remain only in the explicitly advanced external-server path
with an unverified-model caveat. Cloud Keychain and official provider guidance remain.

Deterministic proof includes `ManagedLocalPresentationTests`, managed-provider migration
tests, and `ManagedLocalSetupUITests`; the UI suite stores representative onboarding and
Settings screenshots in its xcresult. Destination-Mac acceptance then exercised the
production GUI from clean isolated storage: Foil downloaded and verified Base English and
Base Multilingual, switched between them, and restored the selected model after relaunch
with outbound HTTPS blocked while loopback remained available. Controlled acoustic playback
through the physical microphone produced exact transcripts with both models; logs record
`mock=false`, captured frames, the owned helper session, and `transcribe.foil.localhost`.
No production Foil installation, TCC reset, or global network change was performed.

### Managed runtime foundation (T002, issue #397)

Implemented the verified-model/session interface documented in
[managed-local-runtime-architecture.md](managed-local-runtime-architecture.md).
The pinned whisper.cpp helper is universal arm64/x86_64 with macOS 14 deployment
targets, static dependencies, embedded Metal source, explicit baseline Intel
instruction settings, and strict nested signing. Existing provider choices stay
separate from explicit managed activation. Installer and language-first GUI work
remain T003/T004; this tranche does not remove current setup commands from the UI.

Evidence on this destination Mac:

- `/tmp/foil-397-t002-unit-tests.xcresult`: full non-live suite, 729 XCTest tests
  and 9 Swift Testing tests, zero failures. This includes real AAC conversion and
  local transcription, expanded-upload rejection, foreign listener survival with
  exactly three bounded attempts, wrong health identity, failed-candidate rollback,
  supersession, cancellation, timeout, and audio cleanup.
- The signed FoilDev helper returned “the quick brown fox jumps over the lazy dog.”
  through the real `transcribe.foil.localhost` hostname, both natively and under
  x86_64 Rosetta. The smoke rejected unauthorized routes and observed child exit
  after parent-pipe EOF. No personal recording or provider credential was used.
- Packaging checks reject missing, corrupt, stale-provenance, thin, and malformed
  runtime artifacts. `codesign --verify --deep --strict` accepts the local app;
  FoilDev and FoilE2E warning-as-error builds pass. Normal app bundles contain no
  model; only the generated test bundle stages the checksum-verified public fixture.
- The initial upstream health contract failed the ownership smoke before the
  lifecycle patch. Later occupied-port and native response decoding failures were
  reproduced and fixed. Swift API tests initially failed compilation while the
  new APIs were absent; that is not an assertion-level RED claim for every test.
- The full suite exposed an existing Keychain write hang. The approved DEBUG-only
  storage override now uses private atomic test files without touching the system
  Keychain; 17 focused tests cover migration, overwrite/delete, and isolation.
  Ordinary application and Release storage remain the existing Keychain path.
- An additional Release warning-as-error audit found existing optimized
  unreachable-code warnings in FoilApp and TranscriptionController. These are
  outside the required Debug warning-clean gate and were not changed here.
  A normal Release build passed, and its executable excludes the DEBUG
  test-storage markers.
- Review regression fixes have focused RED→GREEN receipts under the ignored
  `.research/managed-runtime/review-*.log` files. The cold-cache test first failed
  normal embedding, then proved automatic preparation, warm reuse, corrupt-cache
  repair, failed-repair rejection, and verified test-only model staging. Its
  compiler dependency is a controlled artifact producer; the real pinned build
  script was separately rerun successfully for both architectures.
- Managed validation initially accepted generic HTTP 200/404/405 through ordinary
  transport. It now requires owned health; missing/stopped/foreign session tests
  prove zero ordinary-transport calls. The explicit stop flag also prevents the
  short process-termination race from presenting a stopped session as active.
- Activation initially left missing-cloud-key readiness and stale validation
  results in place. Regression tests now prove healthy managed mode becomes
  ready without a key, resets validation on both transitions, and restores the
  selected cloud provider's credential requirement when deactivated.

Local app/test builds use the repository's established self-signed
`ENABLE_HARDENED_RUNTIME=NO` exception. The helper itself retains hardened-runtime
metadata and strict signing. This is not Developer ID/notarization proof, native
Intel hardware coverage, or execution on macOS 14. Fresh-user GUI downloading,
language selection, microphone transcription, and offline relaunch remain
unverified acceptance work. Nothing was installed into production Foil.

### T003 managed model lifecycle

- Added a bundled immutable base.en/base catalog, explicit unanswered/English-only/
  multilingual intent, exact artifact sizes and hashes, and OpenAI model notices.
- Added the production streaming installer, private partial/journal storage, disk
  preflight, exact HTTP/size/hash validation, exclusive atomic promotion, full
  restart recovery, atomic inventory/selection writes, and verified offline reload.
- AppState/FoilApp now expose install/select/cancel/restore/remove operations;
  the coordinator exposes installed, selected, candidate, and active identities
  plus progress and actionable errors. T004 owns their GUI presentation.
- Candidate health precedes the atomic durable selection commit. The previous
  runtime survives a failed commit. Successful switches retain sessions still
  held by transcription callers; active/candidate/retained models cannot be removed.
- Focused RED→GREEN evidence covers missing catalog resources/recommendations,
  retained session survival, pre-commit persistence failure, disk-space failure,
  HTTP/truncation rejection, missing offline selections, legacy metadata rejection,
  cancellation during initial-provider changes, cancellation-aware hashing,
  recovery/inactive removal, and shared-writable storage rejection.
- Managed setup readiness now additionally requires a running, previously
  health-verified session; missing models and stopped sessions cannot claim Ready.
- Managed connection/setup checks ignore invalid URLs retained for an inactive
  custom provider. Unchanged verified inventory restoration performs no write;
  actual inventory/selection changes retain strict atomic persistence.
- Review regressions exercise production streamed-write ENOSPC after real partial
  bytes, unknown capacity without transaction files, valid unknown-length bodies
  and bounded overflow, plus redirect delegate rejection/sanitization and hop limits.
- Actual clean-store production installation produced base.en, retained base.en,
  and base transcripts. A separate offline process restored base and transcribed
  with zero model-network requests. Receipts are under
  `/tmp/foil-397-t003-model-acceptance`; final verification is recorded in T003's
  Worker receipt. The live scenario also exercises a real read-only-directory
  metadata failure after candidate startup before committing selection.
- The strengthened live scenario holds a real long transcription outstanding
  across activation, checks final lease release and exact child PID exit, and
  removes the now-eligible inactive model. It also injects ENOSPC only at the
  atomic inventory write after real download/verification/promotion, then verifies
  restart recovery. Offline coverage restores with actual read-only permissions
  and with deterministic zero-capacity/ENOSPC metadata storage.
- GUI installation/language selection, a microphone transcript, offline GUI
  relaunch, production distribution signing, native Intel, and macOS 14 execution
  remain separate acceptance milestones. No production application was installed.
