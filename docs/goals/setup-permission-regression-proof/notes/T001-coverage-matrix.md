# T001 Scout Coverage Matrix

## Scope

Mapped the current worktree for setup-permission regression coverage. Evidence includes the uncommitted local fix currently present in `Foil/AppState.swift`, `Foil/FoilApp.swift`, `Foil/OnboardingView.swift`, `FoilTests/AppStateTests.swift`, and `FoilUITests/FoilUITests.swift`.

## Coverage Matrix

| Row | Failure mode / path | Status | Evidence | Missing assertion | Recommended task |
| --- | --- | --- | --- | --- | --- |
| 1 | `AppState.isSetupReady` only becomes true when Accessibility, Microphone, and API key are ready | covered_auto | `Foil/AppState.swift:422`; `FoilTests/AppStateTests.swift:171`; `FoilTests/AppStateTests.swift:209` | None for aggregate readiness. | None. |
| 2 | Accessibility denied state shows "Enable Accessibility" instead of Ready | covered_auto | `Foil/AppState.swift:940`; `FoilTests/AppStateTests.swift:181`; `FoilUITests/FoilUITests.swift:75` | Onboarding-specific Accessibility denied copy is not asserted. | T030. |
| 3 | Microphone unknown state shows a Check action and does not show Ready | covered_auto | `Foil/FoilApp.swift:729`; `FoilUITests/FoilUITests.swift:107`; `FoilUITests/FoilUITests.swift:137` | No fake transition from unknown to authorized through real refresh provider. | T020 then T030. |
| 4 | Microphone denied state shows Open Settings and keeps setup incomplete | partial | `Foil/FoilApp.swift:735`; `FoilUITests/FoilUITests.swift:122` | No onboarding final-step assertion that denied Microphone keeps `Get Started` disabled. | T030. |
| 5 | `applySetupHealth` clears stale denied Accessibility and stale denied Microphone when the system says ready | covered_auto | `Foil/AppState.swift:953`; `FoilTests/AppStateTests.swift:223` | Only `.authorized` is covered; `.denied`, `.restricted`, and `.notDetermined` mappings are not directly tested. | T010. |
| 6 | `refreshSetupHealth()` reads current Accessibility and Microphone status in production | partial | `Foil/FoilApp.swift:708`; `Foil/FoilApp.swift:746`; `Foil/FoilApp.swift:748`; `Foil/FoilApp.swift:749` | No deterministic test can inject platform status; direct macOS APIs make this source-only today. | T020. |
| 7 | Onboarding refreshes setup health when the wizard appears | partial | `Foil/OnboardingView.swift:88`; `Foil/FoilApp.swift:346` wires `onRefreshSetupHealth` | No UI/integration test proves a stale state flips on appear while onboarding is open. | T020 then T030. |
| 8 | Entering the Accessibility step refreshes stale Accessibility state | partial | `Foil/OnboardingView.swift:91`; `Foil/OnboardingView.swift:93` | No test drives a stale Accessibility warning to ready by navigating to step 3. | T020 then T030. |
| 9 | Opening Accessibility settings starts refresh polling | partial | `Foil/FoilApp.swift:765`; `Foil/FoilApp.swift:770`; `Foil/FoilApp.swift:781` | No deterministic assertion that the polling task starts or observes an Accessibility transition. | T020 or a focused AppDelegate test seam. |
| 10 | `applicationDidBecomeActive` refreshes setup health after returning from System Settings | partial | `Foil/FoilApp.swift:315`; `Foil/FoilApp.swift:317` | No test simulates app activation with changed permission facts. | T020. |
| 11 | Setup polling retries hotkey monitor after Accessibility becomes trusted | partial | `Foil/FoilApp.swift:787`; `Foil/FoilApp.swift:788`; `Foil/FoilApp.swift:803` | No deterministic test for polling, retry, or early stop when setup becomes ready. | T020 or a narrower polling unit seam. |
| 12 | Entering the Microphone step refreshes setup health and requests/checks Microphone | partial | `Foil/OnboardingView.swift:95`; `Foil/OnboardingView.swift:97`; `FoilUITests/FoilUITests.swift:137` | Existing UI test uses `--ui-testing` and does not prove real refresh callback behavior. | T020 then T030. |
| 13 | Microphone permission callback refreshes the whole setup model before evaluating final readiness | partial | `Foil/FoilApp.swift:820`; `Foil/FoilApp.swift:822`; `Foil/FoilApp.swift:823` | UI-test path exits early at `Foil/FoilApp.swift:813` and never proves the production callback refresh. | T020 then T030. |
| 14 | `Get Started` becomes enabled after Microphone is checked ready | covered_auto | `Foil/OnboardingView.swift:75`; `Foil/OnboardingView.swift:79`; `FoilUITests/FoilUITests.swift:152`; `FoilUITests/FoilUITests.swift:155` | This covers only seeded Accessibility-ready + Microphone unknown-to-ready, not Accessibility stale-to-ready in the same open wizard. | T030. |
| 15 | Provider/API-key gating does not mask permission readiness | partial | `Foil/AppState.swift:422`; `Foil/AppStateTests.swift:345`; `FoilUITests/FoilUITests.swift:179` | Local-provider no-key onboarding is covered; Groq missing-key final `Get Started` disabled state is not explicitly covered in onboarding. | T030 or T010. |
| 16 | Production cask install identity/signing/notarization smoke | covered_manual | `docs/fresh-machine-homebrew-onboarding-smoke.md:17`; `docs/fresh-machine-homebrew-onboarding-smoke.md:29`; `docs/release-qa-log.md` contains historical cask/signing checks | Current docs do not explicitly tie production identity to stale setup-permission regression rows, and current public version text is stale in places. | T040. |
| 17 | Real TCC reset/fresh-account QA covers stale Accessibility already-granted and grant-while-on-step flows | missing | `docs/fresh-machine-homebrew-onboarding-smoke.md:40` has broad Accessibility/Microphone steps | No row for already-granted Accessibility before step, grant while on Accessibility step, already-granted Microphone, revoked while running, or quit/relaunch after stale-state transitions. | T040. |
| 18 | Release gate requires permission regression matrix before publish | partial | `docs/release-process.md:42` requires DMG Finder QA; `docs/release-qa-log.md` has manual smoke tables | No explicit release gate says run setup permission regression focused tests, production cask smoke, or TCC matrix. | T040 and T050. |

## Gaps Ranked By Risk

1. **No deterministic permission provider seam.** `refreshSetupHealth()` and the microphone callback still depend on direct platform APIs, so tests cannot simulate "System Settings changed while onboarding is open" without live TCC.
2. **Onboarding refresh triggers are source-covered, not behavior-covered.** `onAppear`, Accessibility-step entry, Microphone-step entry, app activation, polling, and microphone callback have source evidence but no fake-transition tests.
3. **Manual QA is broad but not regression-specific.** The fresh-machine Homebrew runbook proves install/onboarding generally, but not the stale-state cases that have regressed.
4. **Provider gating is partly covered.** Local provider no-key setup is covered; Groq missing-key and final button interaction are not explicitly tied to permission-readiness tests.

## Candidate Next Tasks

1. **First largest safe slice:** T020 permission provider seam plus a minimal fake-transition test. This unlocks deterministic proof for rows 6-13 and prevents future UI-only guessing.
2. **Next automated slice:** T030 onboarding UI/integration tests using the seam to prove stale Accessibility and Microphone transitions while the wizard remains open.
3. **Parallel-safe doc slice after automation:** T040/T050 production TCC QA checklist and checked-in coverage matrix, tied to release gates.

## Acceptance Result

PASS. The matrix enumerates 18 rows. Every row has a status, concrete evidence, a missing assertion, and a recommended task. No row uses vague evidence.
