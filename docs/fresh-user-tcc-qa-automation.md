# Mac mini 2 Fresh-User/TCC QA Automation

This package starts the unattended developer-lab lane for issue #365. The first
phase is intentionally non-destructive: it records host identity, runner facts,
tooling, `/Applications/Foil.app` identity, sudo availability, and a structured
operator checklist.

## Quick Start

From the development machine:

```sh
scripts/fresh-user-tcc-qa.sh preflight \
  --host mm2 \
  --expected-hostname Jeremys-Mac-mini-2.local \
  --expected-arch arm64
```

To collect evidence without failing on the currently installed app version:

```sh
scripts/fresh-user-tcc-qa.sh collect --host mm2
```

The script writes a timestamped evidence folder under `/tmp` unless
`--evidence-dir` is provided. The packet includes:

- `host.txt`
- `tooling.txt`
- `sudo.txt`
- `runner.txt`
- `app-identity.txt`
- `summary.txt`
- `operator-notes.md`
- `manifest.json`

## Current Scope

Automated:

- Mac mini 2 allowlist gating.
- IPv6 SSH preflight.
- Host, macOS, architecture, Homebrew, GitHub CLI, Xcode, sudo, runner, and app
  identity capture.
- Expected hostname, bundle id, architecture, version, and build checks when
  requested. The default expected bundle id is `com.neonwatty.Foil`.
- Structured evidence bundle and manual TCC row template.
- Private-artifact warning in the summary and manifest because the packet can
  include local usernames, hostnames, hardware UUIDs, paths, and operator-added
  screenshots.

Intentionally blocked:

- Disposable macOS user creation.
- Disposable user cleanup.
- TCC reset.
- `/Applications/Foil.app` replacement.
- Silent or synthetic privacy grants.

Those require a later root-owned helper or audited narrow sudo path. Do not run
repo-writable scripts as root for user lifecycle or cleanup.

## Manual Experimental Lane

For now, run this harness manually from a development machine with SSH access
to Mac mini 2. Keep a few successful evidence packets before promoting it to a
GitHub Actions workflow.

The later workflow shape should be `workflow_dispatch` only at first, target
`[self-hosted, macOS, ARM64, mac-mini-2, foil]`, fail closed if the runner name
is not `foil-mac-mini-2`, collect local evidence, and upload the packet. That
future workflow would prove the managed lab host is reachable and identifiable.
It would not prove real fresh Microphone prompt consent.

## Consent Lane

Real fresh-user/TCC proof still needs an operator for rows where macOS requires
human consent, especially the first Microphone grant. The generated
`operator-notes.md` marks those rows as `operator_confirmed` so reviewers do not
confuse managed-lab proof with real fresh-prompt proof.

Use `docs/fresh-machine-homebrew-onboarding-smoke.md` as the release oracle for
the human-confirmed rows.
