# Managed Local GUI Acceptance

This acceptance is deliberately separate from `--ui-testing`. Deterministic UI
fixtures may prove rendering, accessibility, and navigation, but they are not
evidence of a real download, microphone transcript, runtime session, or relaunch.

## Non-interactive deterministic UI tests

Run local fixture UI tests with ad-hoc signing so Xcode never needs the Foil
development-certificate private key:

```sh
RUN_LIVE_GROQ_TESTS=0 RUN_LIVE_MICROPHONE_TESTS=0 \
xcodebuild test -scheme Foil -destination 'platform=macOS' \
  -parallel-testing-enabled NO \
  -only-testing:FoilUITests/ManagedLocalSetupUITests \
  FOIL_APP_BUNDLE_IDENTIFIER=com.neonwatty.Foil.UITesting \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual ENABLE_HARDENED_RUNTIME=NO
```

The `--ui-testing` app process derives an isolated temporary root from its test
runner state path. Launch defaults, managed models, history, usage records, and
test credentials stay outside production Foil storage. The UI-test interruption
monitor must never click security-sensitive `Allow`, `OK`, or password controls;
an unexpected macOS security prompt is a failed prerequisite, not something the
suite may approve. Ad-hoc signatures are only for local deterministic tests and
must not be cited as distribution-signing or notarization evidence.

Run the required commands with a newly built `Foil Dev.app` and a new state root.
The driver refuses the production Foil identity, never resets TCC permissions,
never seeds a model or transcript, and never erases an existing state root.

Before setting `FOIL_MANAGED_LOCAL_GUI_APPROVED=1`, approve the visible download,
app termination/relaunch, and UI automation. `FOIL_MANAGED_LOCAL_GUI_PERMISSIONS_READY=1`
asserts that the Foil Dev identity already has user-granted Accessibility and
Microphone permission. `FOIL_MANAGED_LOCAL_GUI_AUDIO_DRIVER` must route a controlled
spoken phrase through the normal microphone path without changing global audio
state. `FOIL_MANAGED_LOCAL_GUI_UI_DRIVER` must drive visible production UI and write
the requested JSON receipt; it may not use `--ui-testing`, direct installer calls,
seeded models/transcripts, or suppressed restoration.

The wrapper parses and validates the receipt; a textual `"status": "passed"`
match is never sufficient. Drivers can exercise the same deterministic validator
without launching Foil:

```sh
bash scripts/test-managed-local-gui.sh \
  --scenario clean-install-switch \
  --state-root /absolute/isolated/state \
  --validate-receipt /absolute/isolated/state/receipt-clean-install-switch.json
```

Validator success proves only that the receipt is structurally complete and its
linked screenshot files exist. Synthetic receipts are useful for validator tests,
but are not live acceptance evidence and must never be filed as destination-Mac
proof.

The script passes `--managed-local-gui-acceptance` and
`FOIL_MANAGED_LOCAL_ACCEPTANCE_ROOT` to the driver. In DEBUG builds that explicit
pair isolates defaults, model storage, history, usage data, and credentials while
leaving the ordinary permission, microphone, onboarding, installer, and restoration
paths enabled. Release builds and ordinary Foil Dev launches ignore this mode.

Every passed receipt uses `schemaVersion: 1`, the exact requested `scenario`,
`status: "passed"`, `fixture: false`, the Foil Dev bundle identifier, the canonical
`stateRoot`, all three production-retention booleans, granted Accessibility and
Microphone observations, verified signing identity/bundle information, and distinct
PNG/JPEG screenshots whose headers report dimensions of at least 32×32. Renaming
text evidence to `.png` is rejected. Clean acceptance requires at least three
screenshots; offline relaunch requires at least two.

The `clean-install-switch` receipt must additionally contain:

- `freshStore.initiallyAbsent: true` and its path matching `stateRoot`.
- `languageChoice` of `englishOnly` or `multilingual`.
- `model` and `switchTargetModel`, each with a different managed catalog ID, the
  exact pinned catalog byte count and lowercase SHA-256, matching downloaded and
  installed byte counts, and `catalogVerified: true`.
- `install` with visible increasing byte samples and successful completion.
- `firstMicrophoneTranscript` with the controlled spoken phrase, nonempty transcript,
  and `normalMicrophonePath: true`.
- `switch` whose from/to identities match those two verified model records, reports
  success, and names the switch target as active.

The `offline-relaunch` receipt must additionally contain:

- `cleanReceiptSHA256` matching the unchanged clean receipt in the same state root.
- Different positive previous/relaunch PIDs and different nonempty managed session IDs.
- `networkTrap.scope: "app-model-host-only"`, a nonempty label, and loopback retained.
- `modelNetworkRequests: 0`.
- Selected and active model IDs matching the clean scenario's switched active model.
- `secondMicrophoneTranscript` proving another normal microphone-path transcript.

Malformed JSON, wrong-scenario receipts, fixture receipts, incomplete objects,
missing screenshots, or broken clean/offline linkage are rejected. The app-scoped
network trap is narrower than physically disconnecting the Mac and must remain labeled.

Deterministic operation coverage remains fixture-labeled and separate from live proof:
presentation tests cover measured download progress, indeterminate verification/startup,
cancel/retry, recovery, failed-switch retained-active messaging, and removal protection;
coordinator/runtime tests exercise failed switching while a healthy owned session remains;
provider tests exercise token-free owned-session connection validation. The managed UI
suite drives download-to-cancel-to-retry through the production button binding. A complete
successful catalog download/switch, removal filesystem transaction, restored connection,
and microphone transcript still belong to the destination-Mac live scenarios above; UI
fixtures must not be cited as those outcomes.

Current destination-Mac gap: this repository does not provide or authorize the
machine-specific audio/UI drivers or user-granted permissions. The script therefore
exits with a `blocked-prerequisite` receipt until those explicit prerequisites exist.
This is not a live acceptance pass.
