# Fresh-Machine Homebrew Onboarding Smoke

Use this runbook for issue #154. The goal is to prove the public install and
first-run setup path from a macOS account that has never installed Foil.

## Environment Rules

- Use a disposable macOS user account, VM, spare Mac, or freshly erased machine.
- Do not wipe an existing user's TCC, Keychain, Homebrew, or Foil data to
  simulate freshness.
- Do not reuse an account that has granted Foil Accessibility, Input Monitoring,
  Microphone, Keychain, or app data permissions.
- Record the macOS version, CPU architecture, and whether the run used a VM,
  spare Mac, or disposable local user.

## Install

Start from a shell where the `mean-weasel/foil` tap is absent:

```sh
brew untap mean-weasel/foil || true
brew tap mean-weasel/foil https://github.com/mean-weasel/homebrew-foil
brew info --cask mean-weasel/foil/foil
brew install --cask foil
```

Record the installed version and build:

```sh
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' /Applications/Foil.app/Contents/Info.plist
/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' /Applications/Foil.app/Contents/Info.plist
```

Verify the installed app is accepted by macOS:

```sh
spctl -a -vv -t execute /Applications/Foil.app
codesign --verify --deep --strict --verbose=2 /Applications/Foil.app
```

## First-Run Walkthrough

1. Launch Foil from `/Applications/Foil.app`.
2. Confirm the first-run onboarding appears.
3. Walk through Accessibility setup from the app-provided action.
4. Walk through Microphone setup from the app-provided action.
5. Configure one provider path:
   - Groq with a throwaway or owner-approved API key, or
   - local transcription if the machine can run the local model path.
6. Run the app's setup check after permissions/provider setup.
7. Use hold-to-record in a disposable target app such as TextEdit.
8. Confirm the transcript is pasted into the target app.
9. Quit and relaunch Foil, then confirm setup state persists.

Do not paste API keys, transcript content containing private data, or Keychain
details into GitHub issues, PRs, or QA logs.

## Real TCC Permission Regression Matrix

Run these rows against the production `/Applications/Foil.app` bundle with
bundle id `com.neonwatty.Foil`. Prefer a fresh disposable macOS account, VM,
spare Mac, or freshly erased machine. If the operator approves `tccutil reset`,
run it only in that disposable environment and only for Foil:

```sh
tccutil reset Accessibility com.neonwatty.Foil
tccutil reset ListenEvent com.neonwatty.Foil
tccutil reset Microphone com.neonwatty.Foil
```

| Row | Starting state | Steps | Expected visible UI | Expected setup/diagnostic state | Result |
| --- | --- | --- | --- | --- | --- |
| Fresh install | No prior Foil TCC, Keychain, or app data. | Install with `brew install --cask mean-weasel/foil/foil`, launch `/Applications/Foil.app`, and open onboarding. | First-run setup appears. Permission rows do not show stale ready state before consent. | Diagnostics are for `/Applications/Foil.app`; bundle id is `com.neonwatty.Foil`. | PASS/FAIL |
| Accessibility already granted | Accessibility is already enabled for `/Applications/Foil.app` before onboarding reaches that step. | Relaunch Foil, go to the Accessibility step. | Step shows `Ready`; `Enable Accessibility` is not shown. | `SetupHealth: accessibilityTrusted=true`. | PASS/FAIL |
| Accessibility granted while on step | Accessibility starts disabled. | Stay on the Accessibility step, enable Foil in System Settings, return to Foil or relaunch if macOS requires it. | The Accessibility step updates to `Ready` without continuing to show `Enable Accessibility`. | `SetupHealth: accessibilityTrusted=true`; hotkey monitor starts after relaunch/check. | PASS/FAIL |
| Microphone prompt grant | Microphone starts not determined. | Stay on the Microphone step and choose the in-app microphone action. Grant the macOS prompt. | Microphone step updates to `Ready`; final `Get Started` becomes enabled once provider/API setup is also ready. | Diagnostics include microphone authorization changing to granted/authorized. | PASS/FAIL |
| Microphone already granted | Microphone is already authorized before onboarding reaches that step. | Relaunch Foil and go to the Microphone step. | Microphone step shows `Ready`; final `Get Started` is enabled when the other setup requirements are ready. | `SetupHealth: microphone=authorized`. | PASS/FAIL |
| Permission revoked while running | Foil is running and previously ready. | Revoke Accessibility or Microphone in System Settings, return to Foil, run Test Setup, then re-enable it. | Setup returns to an actionable state, then returns to `Ready`; `Get Started` is disabled while any required permission is missing. | Diagnostics record the revoked state and the later ready state for the same production app path. | PASS/FAIL |
| Quit/relaunch persistence | Accessibility, Microphone, and provider setup are complete. | Quit Foil, relaunch from `/Applications/Foil.app`, open setup/status. | Setup remains `Ready`; onboarding does not re-block on stale permission text. | Diagnostics show Accessibility trusted, Microphone authorized, and provider/API readiness restored. | PASS/FAIL |

## Evidence Template

Append a completed entry to `docs/release-qa-log.md` or attach it to issue #154:

```md
## Fresh-Machine Public Homebrew Onboarding Smoke

- Date:
- Tester:
- Machine/account type:
- macOS version:
- Architecture:
- Foil version/build:
- Homebrew tap command:
- Homebrew install result:
- Gatekeeper result:
- Codesign result:
- Onboarding appeared on first launch: PASS/FAIL
- Accessibility setup from Foil: PASS/FAIL
- Microphone setup from Foil: PASS/FAIL
- Microphone final Get Started enabled after grant: PASS/FAIL
- Provider setup path tested:
- Setup check after configuration: PASS/FAIL
- Hold-to-record transcription/paste: PASS/FAIL
- Quit/relaunch setup persistence: PASS/FAIL
- Real TCC matrix rows completed:
- Friction observed:
- Follow-up issues filed:
```

## Pass Criteria

- Public Homebrew install succeeds without local repo state.
- Installed app reports the expected version/build for the current public release.
- Gatekeeper and deep strict codesign checks pass.
- First-run onboarding appears for the fresh account.
- Accessibility and Microphone setup can be completed without undocumented
  workarounds.
- Already-granted Accessibility and Microphone show `Ready` during onboarding.
- Accessibility and Microphone changes made while onboarding is open refresh the
  visible state and final `Get Started` enabled state.
- At least one provider path can be configured.
- One hold-to-record transcription successfully pastes into a disposable target.
- Setup state survives quit and relaunch.

File a concrete follow-up issue for each user-visible friction point.
