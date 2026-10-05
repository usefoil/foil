# Agent Access approved actions evidence

## Claim: unrelated Vocabulary changes do not strand proposals

- Strongest realistic failure mode: a second proposal changes the Vocabulary snapshot, leaving the first proposal permanently disabled even though its rules still compile.
- Evidence: `AgentAccessControllerTests.testUnrelatedSecondProposalAllowsRevalidatedReviewedApply` submits two proposals, applies the second, then revalidates and applies the first. `testConflictingSecondProposalBlocksRevalidatedReviewedApply` uses the same sequence with an overlapping active rule and verifies that the first remains pending with a spoken-form and scope explanation.
- Residual risk: a direct external edit to the catalog between main-actor validation and the atomic catalog save still fails closed and requires a retry.

## Claim: agent action requests cannot change settings before Foil approval

- Strongest realistic failure mode: an agent submits a request with an `approved` claim, or posts directly to a status URL, and the setting changes without a Foil decision.
- Evidence: `testAgentCannotClaimApprovalOrChangeSettingsThroughStatusRoute` receives `pending`, a status-route POST receives 405, and local corrections remain off. `testLiveSocketActionRemainsInertUntilFoilDecision` sends a real HTTP request over the owner-only Unix socket, verifies unchanged state, calls the Foil decision path, then reads `approved` over the socket.
- Residual risk: another process with the same macOS user rights can operate Foil's UI or modify its local files; the Agent Access API itself has no approval route.

## Claim: approved changes use Foil validation and leave an audit trail

- Strongest realistic failure modes: retries apply a change twice; a proposal is edited after an apply request; app or group changes bypass Foil's normal setters; a crash after approval loses evidence of the user's decision.
- Evidence: `testAgentActionRequiresFoilApprovalAndReplayIsAudited` covers proposal application, idempotent replay, and durable status. `testApprovedScopeAndAppRoutingUseExistingFoilSetters` verifies correction scope and app assignment remain inert until approved. `testChangedProposalCannotBeAppliedThroughEarlierAgentAction` verifies an edited proposal cannot use the earlier request and that `approved_at` survives cancellation. The store writes an owner-only 0600 audit file.
- Residual risk: if the app stops after changing a setting but before recording final success, the audit state remains `approved_pending_apply`; retry is idempotent, and **Stop retrying** is recorded as `cancelled_after_approval` without claiming the change was undone.

## Verification

- `AGENT_ACCESS_RESULT_BUNDLE=/tmp/foil-agent-action-gate-20261005.xcresult make test-agent-access`: 111 focused tests passed, 0 failed.
- `make test`: 957 passed, 4 skipped, 0 failed in `Test-Foil-2026.10.05_06-59-22--0700.xcresult`.
- `make build-warnings-as-errors`: passed.
- `git diff --check` and `python3 -m json.tool Foil/Resources/AgentAccessOpenAPI.json`: passed.
- `FoilUITests.testAgentActionRequiresVisibleFoilApproval`: compiled but did not execute on this host. The Xcode UI runner timed out while enabling automation mode before Foil launched. Run this test on an interactive Mac UI runner and manually confirm the approval sheet before release.
