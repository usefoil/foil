# T004 Blocker

Result: blocked on macOS Developer Tools security before WDA can expose a physical UI automation endpoint.

## Claim

The v0.21 code slice is installed on the physical phone and App Group staging/reset proof exists, but the required physical keyboard UI receipt cannot be collected until WDA can enable automation mode.

## Evidence

- `iPhone-preview` is visible and paired.
- Device lock state reports `passcodeRequired=false` and `unlockedSinceBoot=true`.
- Device details report Developer Mode enabled, wired transport, CoreDevice tunnel connected, and hardware UDID `00008030-001A0C980A33C02E`.
- Current branch build/install passed and the phone reports Foil iOS `0.1.0 (10)`.
- App Group proof passed for:
  - initial `idle`/no transcript;
  - complete transcript fixture readback with hash-only transcript evidence;
  - stale `processing` + transcript fixture readback with hash-only transcript evidence;
  - final reset to `idle`/no transcript.
- WDA retry command launched the runner and printed `Running tests...`, but neither `http://192.168.1.40:8100/status` nor `http://127.0.0.1:8100/status` became reachable.
- After about one minute, WDA failed with `Timed out while enabling automation mode.`
- The command then prompted for `Password:`.
- `pymobiledevice3 developer wda status` through both the user-local and `/opt/prcard` installs failed with `Failed to connect to service port`.
- `/usr/sbin/DevToolsSecurity -status` reports `Developer mode is currently disabled.`
- `id` shows the user is already in `_developer`, so the missing piece is the password-gated Developer Tools security enablement, not repo signing or device pairing.

## Required Human Action

Run this on the Mac and enter the admin password when prompted:

```bash
/usr/sbin/DevToolsSecurity -enable
```

Then verify:

```bash
/usr/sbin/DevToolsSecurity -status
```

Expected:

```text
Developer mode is currently enabled.
```

After that, resume T004 and retry the WDA runbook command. The remaining proof is:

- stage stale non-complete snapshot, focus sterile host field, prove `Insert latest` is disabled/unavailable in physical Foil Keyboard;
- stage complete snapshot, prove exact-once insertion into a sterile target and App Group cleanup to `idle`/no transcript.
