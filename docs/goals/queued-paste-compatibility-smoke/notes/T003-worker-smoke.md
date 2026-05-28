# T003 Worker Smoke

## Result

done, with incomplete oracle coverage

The worker slice added a repo-native queued-paste compatibility runbook, a local prerequisite smoke wrapper, a Make target, and QA-log entries. The available local prerequisite gates now prove TextEdit target identity mechanics and Chrome textarea paste mechanics, but they do not fully prove real-target queued delivery because the current deterministic queued-paste UI test uses a synthetic Foil target.

## Files Changed

- `docs/queued-paste-compatibility-smoke.md`
- `docs/release-qa-log.md`
- `scripts/run-queued-paste-compatibility-smoke.sh`
- `Makefile`

## Commands Run

- `bash -n scripts/run-queued-paste-compatibility-smoke.sh`
- `make -n test-queued-paste-compatibility`
- `make test-queued-paste-compatibility`
- `ALLOW_LOCAL_QA_SKIP=1 make test-queued-paste-compatibility`

## Evidence

Artifacts:

- `/tmp/foil-queued-paste-compatibility-20260528-042127`
- `/tmp/foil-queued-paste-compatibility-20260528-042347`
- `/tmp/foil-queued-paste-compatibility-20260528-042455`

Final accepted local run:

```sh
ALLOW_LOCAL_QA_SKIP=1 make test-queued-paste-compatibility
```

Result:

- TextEdit installed-app automation reached production `TextInserter.insertAsync` and did not use the UI-test paste bypass.
- TextEdit installed-app automation still hit the known local skip: `/Applications/Foil.app` did not receive the target AX window in this desktop session.
- TextEdit async window-specific target capture passed with `TextEdit pid=89016`.
- SkyLight TextEdit background paste passed with `TextEdit wid=123328` while Finder stayed frontmost.
- Terminal cross-app target passed.
- Chrome textarea target passed.
- VS Code skipped because it is not installed.
- Notes skipped by design to avoid mutating persistent Notes data.

## Remaining Gap

The oracle still requires real-target queued-paste rows for TextEdit and one browser. The runbook records the exact manual procedure, but those rows have not been executed in this agent-controlled session. The fully automated queued path available in `FoilUITests` uses a synthetic `Foil UI Test` target, so it cannot prove app/window return behavior for TextEdit or Chrome.
