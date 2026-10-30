# Installing and switching local model sizes

In **Settings → Transcription**, select **On this Mac — managed**.
Choose your dictation languages, then use **Model size** to choose a model.
English dictation can use all models; other or multiple languages only offers
multilingual models. First-run setup recommends Medium English for English-only
dictation and Base Multilingual for other or multiple languages. Existing saved
model selections are preserved.

Settings offers Tiny, Base, Small, and Medium in English-only and multilingual
variants, plus multilingual Large V3 Turbo and Large V3. Each choice shows its
download size, required disk space, and speed/memory guidance. Merely changing
the picker does not download a model or change the active server.

Choose **Install and use** to download a missing model, check its exact size and
SHA-256, start its bundled server, and switch after the server passes the owned
session health check. The status distinguishes the candidate from the active
model. If download, verification, or startup fails, the previous active model
and saved selection stay intact. Cancel stops the candidate operation.

Choose **Use** for a previously installed model to start and check its server
without downloading again. A transcription already using the previous server
can finish before that server exits. Inactive models can be removed when they
are no longer selected or in use. Foil restores the saved selection on launch;
Settings also offers **Restore selected model** when no session is active.

The **Advanced external local server** mode continues to connect to a server
you manage yourself. Its Terminal setup helper is separate from managed model
installation and switching.

## Verification

Deterministic UI coverage is in `FoilUITests/ManagedLocalSetupUITests`, and
catalog, failure/cancellation, and runtime ownership coverage is in the
`ManagedLocal*Tests` unit/integration suites.

Opt into real Tiny/Base downloads, transcription after switching, offline reuse,
and the Settings install/switch/relaunch flow with:

```sh
TEST_RUNNER_FOIL_RUN_MODEL_SWITCH_ACCEPTANCE=1 RUN_LIVE_GROQ_TESTS=0 \
xcodebuild test -scheme Foil -destination 'platform=macOS' \
  -parallel-testing-enabled NO \
  -only-testing:FoilTests/ManagedLocalModelAcceptanceTests/testLiveTinyToBaseSwitchTranscribesAndReusesInstalledModelsOffline \
  -only-testing:FoilUITests/ManagedLocalSetupUITests/testLiveSettingsInstallSwitchAndRestore
```

The live checks use isolated temporary model stores and download about 226 MB
per store. They retain screenshot/transcription attachments in the test result
bundle. They exercise the bundled runtime; they do not need an external server
or cloud API key. Large-model resource requirements vary by machine; a Tiny/Base
pass does not prove every larger model starts within the runtime’s 30-second
readiness deadline.

Catalog provenance: file sizes and SHA-256 values come from the upstream
[whisper.cpp model repository at the pinned revision](https://huggingface.co/ggerganov/whisper.cpp/tree/5359861c739e955e79d9a303bcbc70fb988958b1).
