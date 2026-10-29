# Local model size switching evidence — 2026-10-29

Branch: `codex/local-model-switching`, created from `origin/main` at
`adcf0f73b9b7e50cc2822e3bef4838dc49ccfa3d` in a separate managed worktree.
Machine: Apple Silicon Mac, 16 GB memory.

## Claims and attempted disproof

| Claim | Strong realistic failure | Evidence |
| --- | --- | --- |
| All advertised sizes are installable, pinned catalog entries. | Incorrect filenames, byte counts, or digests make installs fail, especially the 3.1 GB Large V3 file. | All ten entries were compared to the upstream Hugging Face tree API at revision `5359861c739e955e79d9a303bcbc70fb988958b1`. Exact sizes and LFS SHA-256 values match. Large V3 was also downloaded, verified, started, and used for transcription. |
| Changing models uses the chosen model in a new healthy server. | The UI claims a switch while requests still use the old model/server. | The standalone harness compiled the actual catalog, store, coordinator, and runtime Swift sources. It required a different session UUID, matching active/selected ID, owned health validation, and HTTP 200 transcription after every switch. See the two JSON receipts. |
| Returning to an installed model works. | A repeated selection redownloads or cannot start after replacement. | Real sequences Tiny English → Base English → Tiny English and Tiny English → Large V3 → Tiny English completed and transcribed “the quick brown fox jumps over the lazy dog.” |
| Download/startup failure or cancellation preserves working dictation. | The old server is stopped or the saved model changes before the candidate is healthy. | `testFailedStartupAndCancelledSwitchPreserveDurableAndActiveModel` launches the real helper with invalid model bytes, then cancels a valid candidate. It checks the prior session UUID, exact inventory bytes, selected ID, and owned health. The full runtime suite also checks persistence failure and retained in-flight sessions. |
| Installed-model reuse and restore work offline. | A hidden model download or a stale server makes restoration appear successful. | `testLiveTinyToBaseSwitchTranscribesAndReusesInstalledModelsOffline` starts a new session from durable selection with a rejecting URLProtocol, switches to installed Tiny, transcribes, and asserts zero model-network requests. Its transcript attachment is retained as `live-transcription.txt`. |
| The controls are usable in Settings after setup. | Merely rendering labels hides disabled, inaccessible, or incorrectly wired actions. | All eight `ManagedLocalSetupUITests` pass, including actual download, Base activation, installed Tiny reuse through the picker/Use action, persisted selection, explicit Restore after relaunch, and language filtering. Result bundle: `/tmp/foil-model-switch-ui-final.xcresult`. |

## Standalone runtime proof

The harness used the app's signed bundled helper from
`/tmp/foil-model-switch-build/Build/Products/Debug/Foil.app/Contents/Helpers/whisper-server`.
It downloaded through the production transactional store and called the
production coordinator and session transport directly. It did not substitute a
fixture HTTP server or bypass model verification or health checks.

The exact harness source is retained in `runtime-smoke.swift`. Commands from the
repository root:

```sh
mkdir -p .research/model-switch-smoke
xcrun swiftc -parse-as-library \
  Foil/ManagedLocalModelCatalog.swift Foil/ManagedLocalModelStore.swift \
  Foil/ManagedLocalModelCoordinator.swift Foil/ManagedLocalRuntime.swift \
  docs/evidence/local-model-switching/runtime-smoke.swift \
  -o .research/model-switch-smoke/smoke
.research/model-switch-smoke/smoke
FOIL_MODEL_SWITCH_SMOKE_MODELS=tiny.en,large-v3,tiny.en \
  .research/model-switch-smoke/smoke
```

This harness uses a temporary ignored store under `.research/model-switch-smoke`.
Its receipt outputs are copied here as `tiny-base-receipt.json` and
`tiny-large-receipt.json`. Session UUIDs are public identity fields, not private
request tokens. No production model store or running external server was changed.

## Build and review

- `xcodebuild build` with `OTHER_SWIFT_FLAGS=-warnings-as-errors`, isolated Derived
  Data, and ad hoc signing succeeded. The separate test targets have pre-existing
  unused-variable/trailing-closure warnings and were compiled without promoting
  their warnings to errors.
- Local certificate signing failed with `errSecInternalComponent`; isolated test
  builds use ad hoc signing. Production signing settings were not edited.
- The Homebrew Codex CLI could not run native review due model compatibility.
  The newer bundled CLI successfully ran the toolkit baseline instead.
- Native review found a test-only relaunch inventory-loading error. A fresh
  independent validator accepted it; the UI test was corrected to reenter managed
  mode before explicit Restore, because `--ui-testing` suppresses automatic
  startup restoration.

## Automated verification and limits

The full XCTest unit portion ran 1,024 tests with four opt-in skips and zero
failures; nine additional Swift Testing tests also passed. The four skips were
the older explicitly driven install/overlap acceptance scenario, two older
provisioned Base English/Base Multilingual fixture checks, and the Release-only
local-correction performance gate. The new real Tiny/Base download, switching,
offline restore, and transcript acceptance test ran successfully. These checks
do not require cloud credentials or microphone permission.

The first combined result bundle (`/tmp/foil-model-switch-complete.xcresult`)
contains the passing full unit run and a failed GUI attempt. An unrelated macOS
Phone “Call Failed” alert interrupted the GUI run; the saved screenshot exposed
that obstruction. The corrected GUI flow uses the new primary picker/Use action
and passes separately in `/tmp/foil-model-switch-ui-final.xcresult` (8/8, no skips).

The largest model tested live was full Large V3 (3,095,033,483 bytes); Tiny English
and Base English were also exercised. Other model sizes have exact pinned
catalog verification but were not each downloaded and transcribed during this
run. Performance and the 30-second readiness deadline can differ on other Macs.
The live GUI relaunch test reconstructs inventory through real mode controls and
uses explicit Restore because `--ui-testing` intentionally suppresses automatic
startup restoration; the offline unit test exercises coordinator restoration.

Review coverage: bundled CLI `codex review --base origin/main`, plus independent
correctness, tests, contracts/types, silent-failures, and comments/docs reviewers.
The accepted candidate received a separate validator; correctness/tests were
rechecked after repairs. The final native pass found no high-confidence
issues. Its sandbox could not execute nested Xcode verification; the app build,
unit tests, live runtime probes, and GUI tests documented here ran separately
outside that reviewer sandbox.

Final clean result: `/tmp/foil-model-switch-verified.xcresult` reports Passed,
1,030 passed, zero failures, four skips (1,034 total, including the window-only
screenshot UI check and nine Swift Testing tests). The full unit portion is
1,024 XCTest cases, four skipped, zero failures. The live eight-test Settings
suite passed separately as recorded above.

Visual QA note: the window screenshot shows the model picker, Large V3 size,
and Install and use control, but a lingering macOS login-keychain alert overlays
the window. The screenshot was inspected and is omitted from the delivered
artifacts rather than presented as unobstructed visual proof. The protected
SecurityAgent UI cannot be dismissed through the available computer-use tool;
no credentials were entered or keychain permissions changed. Controls and live
switch/restore actions passed automated GUI checks separately.

## Normally signed app: switching and automatic startup

Follow-up smoke used a fresh FoilDev build signed with `Foil Local Code Signing`,
the same certificate and exact designated requirement as the installed
`/Applications/Foil Dev.app`. Deep/strict signature verification succeeded.
Launch used only `--managed-local-gui-acceptance` plus its isolated storage root;
there was no `--ui-testing`, no seed flags, no direct installer invocation, and
no suppression of normal startup restoration or permission checks.

Through visible UI, Base English was downloaded and activated, then Tiny English
was downloaded and selected. The previous Base child exited normally after the
switch. Normal Cmd-Q stopped both the app and its owned Tiny child. Relaunch with
the same storage root created a different app PID and helper PID, restored
`tiny.en` automatically, and passed owned-session health in 109 ms. No Restore
button or model-selection action was used on relaunch. Home and Settings both
reported Selected/Active Tiny English, and Test connection independently reported
“Owned local session ready.” See `signed-normal-startup/receipt.json`, signing
output, and startup traces for exact identities and timing.

This closes the automatic-restoration gap in the earlier UI-testing proof. It is
local certificate signing evidence, not notarized distribution-build evidence.

**Remaining microphone check:** real Accessibility and Microphone permission
were observed granted; normal microphone capture produced buffers with zero
conversion errors and used the real local provider (`mock=false`). The built-in
speakers were muted (`kAudioDevicePropertyMute == 1`), so system-synthesized speech
could not reach the microphone; the app correctly returned no recognizable
speech. No controlled spoken transcript was observed. The full smoke remains
partial until the user supplies the phrase or approves temporarily unmuting the
speakers and restoring mute afterward. No global audio settings, TCC records,
keychain access rules, or production model/history storage were changed.
