# Foil Local Pairing Bridge V1

## Purpose

Foil Local Pairing Bridge V1 lets a user dictate on iPhone while a paired Mac
does the transcription through the route already configured in the Mac app.
The strategic path is private local transcription: iPhone records, Mac
transcribes with Local whisper.cpp, iPhone receives the transcript for Foil
Keyboard insertion.

This spec is the shared contract for:

- `usefoil/foil#291` bridge product/protocol spec
- `usefoil/foil#293` Mac bridge service skeleton
- `usefoil/foil-ios#39` route-first iOS onboarding
- `usefoil/roadmap#1` local-first program coordination
- `usefoil/roadmap#2` cross-repo launch evidence

## V1 Product Promise

When a user chooses "Use my Mac" on iPhone:

1. The iPhone pairs with a trusted Mac on the local network.
2. The iPhone app records audio.
3. The iPhone sends that audio to the paired Mac over an encrypted local
   session.
4. The Mac transcribes through its selected transcription route.
5. The Mac returns transcript text plus a route receipt.
6. Foil Keyboard inserts the completed transcript through the existing iOS app
   group handoff.

V1 must be honest when this path is unavailable. It may offer "Use an API key
on this iPhone" as a fallback, but it must not imply the iPhone is using the Mac
unless the Mac actually handled the request.

## Non-Goals

- Account/cloud bridge.
- Cross-network relay.
- Background keyboard-owned recording or networking.
- Silent credential transfer.
- Multi-Mac routing policy beyond selecting one paired Mac.
- Public claims before physical-device proof.

## Names

Stable names prevent Mac and iOS workers from inventing incompatible terms.

| Concept | V1 Name |
| --- | --- |
| Protocol family | `foil.localBridge` |
| Protocol version | `1` |
| Mac service name | Foil Local Bridge |
| Pairing state | `unpaired`, `pairing`, `paired`, `revoked` |
| Request state | `queued`, `uploading`, `transcribingOnMac`, `complete`, `failed`, `cancelled` |
| Route receipt object | `RouteReceipt` |
| iOS route label | `Use my Mac` |
| iOS fallback label | `Use an API key on this iPhone` |

## Ownership

### Mac App

- Advertises local availability only when the bridge service is enabled.
- Shows pairing code or QR payload.
- Stores trusted iPhone identities.
- Revokes paired iPhones.
- Receives audio requests.
- Runs transcription through the selected Mac route.
- Returns transcript, route receipt, and failure details.
- Logs bridge diagnostics without transcript text, API keys, or raw audio.

### iOS App

- Owns pairing UX.
- Records audio in the containing app.
- Sends audio to the paired Mac.
- Stores trusted Mac identity in Keychain.
- Receives transcript and route receipt.
- Writes the completed transcript to the existing app group handoff.
- Shows fallback setup for on-iPhone API key use.

### iOS Keyboard Extension

- Does not own recording, pairing, or networking in V1.
- Reads completed transcript state from the app group.
- Inserts once using the existing exact-once behavior.
- Shows enough status to send the user back to the app when pairing or
  transcription is needed.

## Discovery

V1 should use local network discovery suitable for Apple platforms, expected to
be Bonjour via Network.framework.

Advertising name:

```text
_foil-bridge._tcp.local
```

TXT fields:

```text
protocol=foil.localBridge
version=1
deviceName=<redacted-friendly Mac name>
supportsLocalTranscription=true|false
supportsCloudTranscription=true|false
supportsCredentialOffer=false
```

The TXT record must not include API keys, transcript text, user identifiers, or
full route configuration.

## Pairing

V1 pairing should use an explicit user-mediated ceremony.

Recommended ceremony:

1. Mac opens "Pair iPhone" and displays a QR code plus short numeric code.
2. iPhone scans QR code or enters code.
3. iPhone and Mac establish an encrypted session.
4. Mac asks the user to approve the iPhone by display name.
5. Both devices store a long-lived trusted peer identity.

Pairing payload:

```json
{
  "protocol": "foil.localBridge",
  "version": 1,
  "macPeerID": "mac-peer-public-id",
  "pairingNonce": "base64url-random",
  "host": "mac.local",
  "port": 49321,
  "code": "123456"
}
```

Storage:

- Mac stores trusted iPhone public identity and display name.
- iOS stores trusted Mac public identity and display name.
- Long-lived secrets belong in Keychain.
- Pairing records must be revocable from both devices.

## Transport Security

V1 requires encryption and peer authentication after pairing.

Minimum contract:

- The first pairing exchange is user-mediated by QR/code.
- Every transcription request uses an encrypted local session.
- Each side verifies the paired peer identity before accepting requests.
- Requests include a nonce or request ID to prevent accidental replay.
- Logs never include raw audio, transcript text, or credentials.

Implementation can choose TLS with pinned self-signed peer identity, Noise, or
another audited local encrypted channel. The chosen implementation must be
documented before Mac/iOS implementation begins.

## Capability Handshake

The iPhone asks the Mac what it can do before sending audio.

Request:

```json
{
  "type": "CapabilitiesRequest",
  "protocol": "foil.localBridge",
  "version": 1,
  "iosAppVersion": "0.1.0",
  "requestID": "uuid"
}
```

Response:

```json
{
  "type": "CapabilitiesResponse",
  "protocol": "foil.localBridge",
  "version": 1,
  "requestID": "uuid",
  "macAppVersion": "1.13.4",
  "routes": [
    {
      "routeID": "localWhisper",
      "displayName": "Local whisper.cpp",
      "available": true,
      "privacyClass": "local"
    },
    {
      "routeID": "groq",
      "displayName": "Groq",
      "available": true,
      "privacyClass": "cloud"
    }
  ],
  "selectedRouteID": "localWhisper",
  "maxAudioBytes": 26214400,
  "acceptedAudioFormats": ["m4a", "wav", "flac"]
}
```

Route IDs:

- `localWhisper`
- `groq`
- `openAIWhisper`
- `customOpenAICompatible`

These names should match route receipts and UI copy.

## Transcription Request Lifecycle

The containing iOS app owns the request.

1. `CapabilitiesRequest`
2. `TranscriptionStart`
3. binary audio upload or chunk stream
4. zero or more `TranscriptionStatus`
5. `TranscriptionComplete` or `TranscriptionFailed`
6. iOS app group write for keyboard insertion

`TranscriptionStart`:

```json
{
  "type": "TranscriptionStart",
  "protocol": "foil.localBridge",
  "version": 1,
  "requestID": "uuid",
  "audio": {
    "format": "m4a",
    "durationMilliseconds": 8400,
    "byteCount": 248112
  },
  "requestedRouteID": "selectedOnMac",
  "languageHint": "en",
  "cleanupMode": "macDefault"
}
```

`TranscriptionStatus`:

```json
{
  "type": "TranscriptionStatus",
  "requestID": "uuid",
  "state": "transcribingOnMac",
  "display": "Transcribing on Neon MacBook Pro"
}
```

`TranscriptionComplete`:

```json
{
  "type": "TranscriptionComplete",
  "requestID": "uuid",
  "transcript": "Example dictated text.",
  "routeReceipt": {
    "routeID": "localWhisper",
    "routeDisplayName": "Local whisper.cpp",
    "transcriptionLocation": "pairedMac",
    "providerLocation": "localMac",
    "cleanupRouteID": "none",
    "audioLeftIPhone": true,
    "audioReachedMac": true,
    "audioReachedCloudProvider": false,
    "textReachedCloudProvider": false,
    "macDeviceName": "Neon MacBook Pro",
    "completedAt": "2026-06-09T19:00:00Z"
  }
}
```

## RouteReceipt

`RouteReceipt` is user-facing evidence. It answers "where did my audio and text
go?"

Required fields:

| Field | Meaning |
| --- | --- |
| `routeID` | Stable route ID used by Mac settings |
| `routeDisplayName` | User-facing route name |
| `transcriptionLocation` | `pairedMac` or `thisIPhone` |
| `providerLocation` | `localMac`, `cloudProvider`, or `customEndpoint` |
| `cleanupRouteID` | Stable cleanup route ID or `none` |
| `audioLeftIPhone` | True when audio was sent to Mac or provider |
| `audioReachedMac` | True when paired Mac received audio |
| `audioReachedCloudProvider` | True when route sent audio to cloud |
| `textReachedCloudProvider` | True when cleanup sent text to cloud |
| `macDeviceName` | User-facing paired Mac name |
| `completedAt` | ISO-8601 completion timestamp |

Example UI copy:

- "Transcribed on your Mac using Local whisper.cpp."
- "Transcribed on your Mac using Groq. Audio was sent from Mac to Groq."
- "Transcribed on this iPhone using OpenAI Whisper."

## Failures

Failures must preserve user trust and avoid dead ends.

| Failure | iOS User Message | Next Action |
| --- | --- | --- |
| Mac unavailable | "Your Mac is not reachable." | Retry, choose iPhone API key, or repair pairing |
| Pairing revoked | "This iPhone is no longer paired with that Mac." | Pair again |
| Mac has no route | "Your Mac needs a transcription route." | Open Mac setup instructions |
| Local route down | "Local whisper.cpp is not running on your Mac." | Show Mac route receipt and setup hint |
| Upload interrupted | "Audio did not finish sending to your Mac." | Retry from retained local audio if available |
| Transcription failed | "Your Mac could not transcribe this recording." | Preserve audio if retry policy allows |
| Keyboard not ready | "Transcript is ready in Foil. Enable Foil Keyboard to insert it." | Open keyboard setup |

Mac failure responses should use stable codes:

- `macUnavailable`
- `pairingRevoked`
- `noTranscriptionRoute`
- `routeUnavailable`
- `uploadInterrupted`
- `transcriptionFailed`
- `keyboardHandoffUnavailable`
- `unsupportedProtocolVersion`

## Credential Handoff

Credential handoff is optional and not part of the first bridge proof.

Rules when added:

- It is always explicit and per-provider.
- The sending device says exactly which provider key is being offered.
- The receiving device stores the key in Keychain.
- The bridge never transfers all credentials in bulk.
- The route receipt never exposes credential material.
- Users can decline and continue using Mac transcription without copying keys.

Suggested message names:

- `CredentialOffer`
- `CredentialAccept`
- `CredentialDecline`
- `CredentialTransferComplete`

## Observability

Diagnostics should make support possible without exposing private content.

Allowed:

- request ID
- route ID
- request state
- byte count
- duration
- error code
- peer display name
- timing milestones

Not allowed:

- transcript text
- raw audio
- API keys
- clipboard contents
- full credential identifiers

## Test Fixtures

Mac and iOS workers should share JSON fixtures for:

- capabilities with local route selected
- capabilities with cloud route selected
- successful local transcription receipt
- successful cloud transcription receipt
- Mac unavailable failure
- route unavailable failure
- unsupported protocol version failure

Fixture location can be decided during implementation, but the payload shapes
above are the canonical V1 starting point.

## Launch Evidence Gates

Before public claims change:

1. Mac unit or integration proof validates route receipt generation for each
   route ID.
2. iOS proof shows "Use my Mac" and "Use an API key on this iPhone" are distinct
   setup paths.
3. Physical-device proof shows iPhone audio sent to paired Mac and transcript
   returned to iPhone.
4. Local route proof shows `audioReachedCloudProvider=false` when Local
   whisper.cpp is selected.
5. Failure proof shows Mac unavailable and route unavailable states do not lose
   the user's visible recovery path.

