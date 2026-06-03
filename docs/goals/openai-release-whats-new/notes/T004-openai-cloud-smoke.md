# T004 OpenAI Cloud Smoke

Claim: The merged OpenAI Whisper provider/service path can transcribe the known Foil E2E WAV through the real OpenAI cloud API using the local `.env.local` key without exposing the secret.

Strongest realistic failure mode: Deterministic tests pass locally or in CI but the real OpenAI Whisper API rejects the key/request, returns an unusable transcript, or leaks the API key into logs.

Evidence:
- `.env.local` contains `OPENAI_API_KEY`; only key length was inspected, not the value.
- `set -a; source .env.local; set +a; make test-live-openai` exited `0`.
- The command built and ran `FoilE2E` with `E2E_TRANSCRIPTION_PROVIDER=openai` and `E2E_TRANSCRIPTION_MODEL=whisper-1`.
- `local-e2e-output.txt` ended with:
  - `[FoilE2E] transcribe: response status=200 responseBytes=45`
  - `[FoilE2E] transcribe: success textLength=44`
  - `status=pass`
  - `transcript=The quick brown fox jumps over the lazy dog.`
- The command echo showed `E2E_API_KEY="${OPENAI_API_KEY}"`, not the secret value. The captured output contains no API key.

Installed-release-app smoke gap:
- The notarized QA app is a `Release` archive from `.github/scripts/build-notarized-qa-dmg.sh`.
- Source inspection shows the deterministic app-level `--e2e-transcribe` canned-audio hook is inside `#if DEBUG` in `Foil/UITestingController.swift` and result writing in `Foil/FoilApp.swift` is also inside `#if DEBUG`.
- Therefore the currently installed notarized Release app cannot run the same deterministic canned-audio OpenAI smoke through launch arguments. The installed app has been verified for identity/signing/notarization/launch in T003; the live cloud transcription path has been verified by `FoilE2E` here.

Residual risk / follow-up: To fully satisfy "installed Release app performs deterministic OpenAI smoke," add a release-safe, opt-in QA hook or a signed helper included in QA artifacts, then rebuild/notarize/install again and rerun the smoke from `/Applications/Foil.app`.
