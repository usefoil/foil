# Agent Access vocabulary — Tranche 0 evidence

Date: 2026-09-21

Branch: `codex/agent-vocabulary-intake`

Host: MacBook Air, arm64, macOS 26.5.1; Xcode 26.3 (17C529)

## Claim: the discovery contract is bounded and matches its documentation

Strongest realistic failure mode: malformed or oversized HTTP is accepted, the
OpenAPI document drifts from the runtime, or the read-only tranche advertises a
Vocabulary mutation that does not exist.

Evidence:

- Focused `xcodebuild test` ran `AgentAccessHTTPTests` and
  `AgentAccessServerTests`: **27 passed, 0 failed, 0 skipped**. Result bundle:
  `/Users/jeremywatt/Library/Developer/Xcode/DerivedData/Foil-cxdqhkzjzbfszhgrfsgtuabghavg/Logs/Test/Test-Foil-2026.09.21_12-14-17--0700.xcresult`.
- Parser cases cover fragmented requests, hard header/body limits, duplicate
  headers and lengths, chunked transfer, unsupported method/version/content type,
  nonnumeric lengths, control bytes, invalid header and body UTF-8, traversal,
  trailing bytes, and request-ID bounds.
- Contract tests compare the exact two implemented paths, all six limits, all
  privacy exclusions, stable proposal states, the resolved socket path, and the
  generated bootstrap command.
- `python3 -m json.tool Foil/Resources/AgentAccessOpenAPI.json`,
  `plutil -lint Foil.xcodeproj/project.pbxproj`, and `git diff --check` pass.

Residual risk / follow-up: this tranche intentionally has no app lifecycle or
setting. Tranche 1 must prove the setting defaults off and controls the server.

## Claim: the Unix-socket boundary fails closed

Strongest realistic failure mode: another user connects, an unsafe filesystem
entry is deleted, a slow client holds resources indefinitely, a disconnect kills
Foil with `SIGPIPE`, or shutdown removes a replacement file it did not create.

Evidence:

- The live test uses `/usr/bin/curl --unix-socket` and verifies a `0700` support
  directory plus a `0600` socket.
- Tests exercise `getpeereid` UID matching, wrong-owner/type rejection, stale owned
  socket replacement, active-server lock contention, regular-file and symlink
  preservation, path escape and overlength rejection, absolute request deadlines,
  active-connection shutdown, and inode-checked cleanup.
- The first disconnect test disproved the initial implementation by crashing the
  test host with signal pipe. The corrected implementation skips writes after EOF
  and uses `MSG_NOSIGNAL`; final partial-request and complete-request disconnect
  tests both leave the server responsive to a subsequent real curl request.

Residual risk / follow-up: a real foreign-owned socket cannot be created by this
unprivileged test process. The production decision function is tested directly
with a mismatched UID, while live filesystem tests cover non-sockets and symlinks.

## Claim: the new module does not regress adjacent Foil behavior

Strongest realistic failure mode: focused tests pass while another unit caller,
the existing local-correction engine, the development brand, or warning-clean CI
breaks.

Evidence:

- Final `make test`: **869 passed, 0 failed, 4 skipped**. The skips are the existing
  opt-in live tests. Result bundle:
  `/Users/jeremywatt/Library/Developer/Xcode/DerivedData/Foil-cxdqhkzjzbfszhgrfsgtuabghavg/Logs/Test/Test-Foil-2026.09.21_12-15-14--0700.xcresult`.
- `make test-local-correction-engine` passed its 18 harness tests and the 150-case
  production engine gate with all deliberate mutants rejected.
- Final `make build-warnings-as-errors` passed.
- `make build-dev` passed. Direct SHA-256 inspection showed the source OpenAPI file
  and both Foil/Foil Dev bundled copies were identical.

Residual risk / follow-up: no UI or installed-app smoke applies yet because Tranche
0 deliberately does not start the server from Foil. Those become required in
Tranche 1 and the final installed-proof tranche.
