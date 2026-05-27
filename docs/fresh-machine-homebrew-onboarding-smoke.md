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
- Provider setup path tested:
- Setup check after configuration: PASS/FAIL
- Hold-to-record transcription/paste: PASS/FAIL
- Quit/relaunch setup persistence: PASS/FAIL
- Friction observed:
- Follow-up issues filed:
```

## Pass Criteria

- Public Homebrew install succeeds without local repo state.
- Installed app reports the expected version/build for the current public beta.
- Gatekeeper and deep strict codesign checks pass.
- First-run onboarding appears for the fresh account.
- Accessibility and Microphone setup can be completed without undocumented
  workarounds.
- At least one provider path can be configured.
- One hold-to-record transcription successfully pastes into a disposable target.
- Setup state survives quit and relaunch.

File a concrete follow-up issue for each user-visible friction point.
