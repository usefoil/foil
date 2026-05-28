# T004 Follow-Ups

## Result

done

The compatibility smoke exposed follow-up work rather than a completed tranche.

## Follow-Ups

1. Complete manual real-target queued-paste rows.
   - Scope: TextEdit disposable document, Chrome or Safari text field, and closed/unavailable target.
   - Required evidence: app/window identity, `Transcript queued`, `Paste Next`, destination result, focus result, and artifact path.
   - Stays in GoalBuddy until the rows are recorded.

2. Consider a bounded automation-only test hook for real-target queued delivery.
   - Scope: capture the real frontmost target, enqueue a mock transcript, and expose a deterministic `deliverNext` trigger without changing product UX.
   - Required guardrails: debug/UI-test/automation-only, no global hotkey, no overlapping recording/transcription architecture.
   - Candidate later PR if manual smoke remains too brittle.

3. Investigate installed-app TextEdit AX-window exposure.
   - Scope: `/Applications/Foil.app` reached production `insertAsync`, but this desktop session did not expose the target AX window to the app process.
   - Required evidence: whether refreshing Accessibility permission for `/Applications/Foil.app` removes the skip.
   - Track as local QA reliability unless it reproduces on a clean user environment.

4. Keep app-specific compatibility findings separate from hotkey delivery.
   - Scope: browser focus quirks, window identity failures, and fallback/manual-paste behavior.
   - Do not fold global queue delivery hotkey work into this smoke tranche.

