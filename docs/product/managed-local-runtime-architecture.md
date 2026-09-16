# Managed local transcription runtime

## Scope and interface

T002 provides the bundled runtime and verified-model-to-transcript path. Model
catalogs, transactional downloading, language-first setup, and complete switching
UX remain T003/T004 work. A preverified tiny.en fixture supplies deterministic
runtime evidence; it is not a product model recommendation.

`ManagedLocalModel.verify(url:id:size:sha256:)` accepts installer-owned files only
after regular-file, exact-size, and SHA-256 checks. `ManagedLocalRuntime.start`
rechecks those bytes before every launch. `AppDelegate.startManagedLocalModel`
commits the separate managed selection only after the candidate is healthy.
The old session stays available when a candidate fails. T003 must preserve
verified immutable model files while sessions use them and finish transactional
installation/deletion semantics.

AppState exposes `managedLocalRuntime.state`, its current session, and restoration
errors for T004. Existing cloud, custom, and external-local provider preferences
remain stored. Selecting one explicitly deactivates managed mode. A selected but
unready managed provider fails closed; it never delegates to the old URL. Relaunch
revalidates the saved model and starts a new session with new credentials.
Activation and deactivation refresh credential-derived readiness and discard the
previous provider's connection-test result. Managed connection validation calls
only the current session's exact health contract, never the ordinary injected
HTTP transport or a token-free `/models` URL. Missing, stopped, and foreign
sessions fail validation, including generic 200/404/405 responses.

## Ownership and transport

The helper lives at `Contents/Helpers/whisper-server`. Each launch obtains a
dynamic loopback port, a random 256-bit path token, and a session UUID. Port
allocation races are bounded to three attempts. Readiness has a 30-second bound;
success requires the current child still running and an exact health object:
service, status, session UUID, model SHA-256, and PID.

The logical endpoint is
`http://transcribe.foil.localhost:<port>/<private-launch-token>/v1`.
Health and transcription are the only accepted routes. The helper rejects
incorrect Host headers and missing/wrong token paths. Upstream `/load`, public
content, and conversion through ffmpeg are inaccessible. Its static directory is
a fresh private empty directory. Child output is discarded so request paths and
tokens do not enter application logs. Only a token-free display address and
generic errors are exposed; provider settings never contain a token.

The native client resolves the actual hostname, rejects any resolution other
than `127.0.0.1` or `::1`, and uses Network.framework with the loopback interface
required and proxies bypassed. This interface constraint remains effective if
name resolution changes between validation and connection. The bounded HTTP/1.1
client requests connection close and accepts unambiguous Content-Length framing.
It rejects redirects and transfer encoding instead of following another URL.

An app-owned stdin pipe defines the child lifetime. EOF exits the helper even
during model loading; app termination, cancelled startup, and superseded startup
release the matching child's pipe. No process is discovered or terminated by
port. A candidate can become active only while its launch generation is current.

## Audio

Managed transport converts input through AVAudioConverter to mono 16 kHz,
16-bit little-endian PCM WAV. A scope owns the temporary file through upload and
removes it on success, failure, or cancellation. Source files remain untouched.
The converted upload size is checked again, and multipart filename/content type
come from the WAV format. Existing external and cloud requests retain their
original audio format. Managed mode does not read or transmit a provider API key.

## Reproducible packaging

`scripts/managed-whisper-runtime.lock.json` records the immutable whisper.cpp
v1.9.4 commit, official CMake release digest, and model revision/size/SHA-256.
`scripts/build-managed-whisper-runtime.sh` verifies tooling before execution,
uses fresh ignored worktree caches, applies the owned lifecycle patch, builds
arm64 and x86_64, and combines them with lipo. Models and executable artifacts are
not committed. Tests stage the verified public model only in the generated test
bundle; normal app bundles contain no model.

Normal Foil/FoilDev build phases self-prepare an absent or invalid runtime through
the pinned build script, then audit again before signing. A preparation lock
serializes concurrent build targets; failed preparation remains a build failure.
`FOIL_MANAGED_RUNTIME_CACHE` may select a build cache; its default is the
worktree-relative `.research/managed-runtime`. The test-only staging phase also
prepares a missing/invalid model and checks the lock's exact size and checksum.
Fresh source builds require network access for pinned prerequisites; subsequent
valid cached builds do not. Packaging regression tests run the real embedding,
audit, and signing paths in a cold miniature checkout with only the expensive
compiler build replaced by a controlled artifact producer. The real pinned build
script is independently executed for both architecture slices.

Both slices target macOS 14. Shared ggml dependencies, dynamic backend loading,
native-host optimization, OpenMP, CUDA/HIP/MUSA, Vulkan, RPC, SYCL, OpenCL,
OpenVINO, WebGPU, and CoreML are disabled. CPU, Accelerate, and embedded Metal
are enabled. Intel AVX, AVX2, BMI2, FMA, F16C, SSE4.2, and AVX512 are explicitly
disabled; the x86_64 slice uses the baseline target instead of the build host's
instruction set. Metal kernels are embedded as source in `__ggml_metallib` and
compiled by the system at runtime without external resource downloads.

Embedding rejects missing/malformed runtime metadata, hash/patch/commit drift,
non-universal binaries, incorrect minimum OS, missing Metal resources, and
non-system dynamic dependencies. It signs and strictly verifies the helper
before the containing app's normal signing phase. Runtime startup checks the
helper's code signature again.

The local self-signed identity requires the repository's existing
`ENABLE_HARDENED_RUNTIME=NO` app/test exception. The helper retains hardened-runtime
metadata and strict signature verification. This is local development evidence,
not Developer ID, notarization, native Intel hardware, or macOS 14 execution proof.
Those distribution/device checks remain final acceptance work.

Test hosts activate the existing DEBUG storage override before constructing
AppState. The override uses isolated, atomic temporary files (0700 directory,
0600 files) keyed by service/account identity, with no system Keychain fallback.
It is absent from Release and inactive during ordinary Debug app execution.
This avoids credential dialogs in deterministic tests; it is not a replacement
for production Keychain storage or live Keychain migration acceptance.

## Failure-oriented evidence

The shell smoke first failed against upstream health because it lacked ownership
identity. The patched helper passed exact identity, rejected routes, synthetic
speech, and parent-EOF checks. The synthetic transcript was “the quick brown fox
jumps over the lazy dog.”

Swift tests exercise model replacement/corruption, unready provider isolation,
native audio conversion and cleanup, actual hostname transport, redirect/framing
rejection, real AAC-to-transcript, failed candidate rollback, cancellation,
supersession, timeout, and occupied-port ownership. Packaging tests reject corrupt,
stale-provenance, thin, malformed, and missing artifacts. These tests establish
only the scenarios that have passing execution receipts; fixture tests do not
establish fresh-user GUI installation or offline relaunch acceptance.

## Managed model service (T003)

The bundled `ManagedLocalModels.json` pins Hugging Face repository
`ggerganov/whisper.cpp` at `5359861c739e955e79d9a303bcbc70fb988958b1`.
The authoritative revision API supplies base.en (147,964,211 bytes,
`a03779c86df3323075f5e796cb2ce5029f00ec8869eee3fdfb897afe36c6d002`) and
base (147,951,465 bytes,
`60ed5bc3dd14eea856493d334349b405782ddcaf0028d4b5df4088345fba2efe`).
The model notices include OpenAI's MIT attribution. There is no runtime catalog
fetch or mutation. Explicit English-only intent recommends base.en; other or
multiple languages recommend base. Unanswered intent remains unanswered and
does not derive from locale or the existing automatic transcription language.

`AppState.managedLocalModels` exposes installed, selected, active, and candidate
identities separately. Its operation state reports recovery, received/total
download bytes, verification, startup, cancellation, and failures. Installed
files alone never constitute readiness. AppState/FoilApp expose install/select,
cancel, restore, and explicit inactive-model removal operations for the T004 UI.
An idle coordinator with installed files and no active session is installed but
inactive; failures can coexist with a healthy previous active session.

The store defaults to the current app bundle identity's Application Support
directory. It rejects symlink roots and shared-writable/foreign-owned roots,
checks owned file types, and derives every final filename from the bundled
revision/digest/model ID. Downloads use an ephemeral URLSession without provider
credentials, cookies, or credential storage. Redirects require HTTPS on the
reviewed Hugging Face hosts (`huggingface.co`, `us.aws.cdn.hf.co`, and
`cas-bridge.xethub.hf.co`); downgrade, credentials in URLs, alternate ports, and
unreviewed hosts are rejected. A new CDN host requires a reviewed app update.

Each download has a UUID-qualified journal and an exclusively created partial
file. A successful HTTP response, bounded bytes, exact final size, and SHA-256
are required. File work and hashing run off MainActor with cancellation checks.
Free-space preflight requires the incoming model size plus 64 MiB for metadata
and safety headroom; retained models already consume the reported free space.
Promotion is a same-filesystem `RENAME_EXCL`, with no second full-sized staging
copy and no overwrite of an existing immutable final file. An existing corrupt
final remains unavailable; choose another verified model, then explicitly remove
the eligible inactive copy before reinstalling it.

Recovery deliberately uses a full restart rather than HTTP range resumption.
Only a valid recorded transaction's owned partial is cleaned up. Interrupted
promotion/inventory writes are reconciled by verifying the catalog-qualified
final files again. Inventory metadata cannot authorize arbitrary paths, sizes,
or digests. The committed selection is preserved even when its file is missing
or corrupt, with an actionable failure and alternative installation choices.

Candidate startup validates the model, signed helper, loopback route, and exact
owned health before the synchronous atomic selection-write boundary. There is
no actor suspension between that write and runtime activation. Write failure
keeps the previous session and durable selection. Concurrent operations cancel
and drain their predecessor; provider changes invalidate pending initial
downloads as well as managed switches. Late progress cannot overwrite later
startup/completion states.

Successful switches release the runtime's strong reference to the prior session
without stopping sessions retained by providers/transcription requests. Such
references protect audio conversion and HTTP response completion. Weak retired
session tracking supports explicit app shutdown and prevents removal while any
active, candidate, or retained session still uses that model. The upstream
`/load` route remains unused.

Launch restoration reads the bundled catalog and verified local store only.
An unchanged verified inventory is not rewritten, allowing restoration from a
readable but temporarily unwritable/full store. Actual reconciliation and
selection changes still require atomic durable persistence. Managed connection
and setup validation use the effective owned provider, not a preserved custom
preset's URL.
Preference-supplied legacy managed-model paths/hashes are explicitly unsupported
for migration and never silently remapped. Existing cloud/custom/external model
and provider preferences are retained. Process-level acceptance is run through
`scripts/test-managed-local-models.sh`; its clean-store scenario downloads both
models through the production Swift installer, and its separate offline process
blocks model-network requests. This does not replace fresh-user GUI, microphone,
Developer ID/notarization, native Intel, or macOS 14 evidence.
