# Codex text cleanup experiment

Open **Agent Access → Try transcript cleanup**. Install Codex CLI and sign in
with `codex login` first. Foil finds the native Codex executable in common
Homebrew/npm, user-local, or desktop-app locations. “CLI found” confirms discovery,
not authentication; the first cleanup checks hosted model access.

Click **Load example**, then **Clean up with Codex**. The example supplies the
preferred terms Supabase and Vercel without modifying your Vocabulary. Or paste
up to 8 KiB of text and select an enabled Cleanup Group. Foil supplies preferred
terms and enabled correction aliases for that group, respecting global overrides
and suppressions. Disabled local corrections are not supplied as aliases.

Codex runs on the Mac using the selected hosted OpenAI model and the user's CLI
sign-in. The initial selection is `gpt-5.5`. This is not on-device inference. The panel explicitly discloses that
entered text and selected Vocabulary go to OpenAI. It is independent of the
Vocabulary socket's enable switch: each **Clean up with Codex** click authorizes
one explicit submission. No background cleanup is enabled.

The output appears alongside the original. The smallest contiguous changed area
is highlighted; this is not a word-by-word diff. Review the result, then optionally
copy it. Cancel stops the local invocation and discards late results. Requests
time out after 60 seconds. Cancellation cannot retract text already sent to the
hosted service. Errors preserve the input and never insert fallback or late text.

## Model, instructions, and timing

The **Model** field is saved on this Mac. **Choose model** loads suggestions from
an isolated Codex app-server catalog session; the catalog can be bundled with the
installed CLI and does not verify account access. You can enter a model ID when
it is missing from the catalog. Cleanup itself uses the existing CLI sign-in;
an unavailable model produces a run error without changing the saved selection.
The initial `gpt-5.5` selection retains low reasoning effort. Other models use
their own default effort, so model comparisons may also differ in reasoning.

Expand **Cleanup instructions** to edit the saved wording/style prompt or restore
the default. Instructions are limited to 8 KiB and can request concise or informal
wording; the fixed request contract still preserves meaning and treats dictation
as data. Model and instructions are local settings shared by this experiment's
Vocabulary selections, not changes to a Cleanup Group's recording settings.
A run snapshots its configuration; editing settings invalidates an older result.

**Timing details** separates local preparation, launch-to-turn-start, the Codex
turn, and finalization, plus input/cached/output token counts when supplied by the
CLI. The turn interval includes connection/waiting/model work; it is not a
measurement of server inference alone. Only model ID, durations and token counts
are written to Foil diagnostics. Raw event content, instructions and transcripts
are not logged. The UI accepts a validated answer only after `turn.completed`,
then stops/reaps the ephemeral process to avoid waiting for post-turn shutdown.

Recording integration, reusable templates, and a persistent cleanup server remain
future work. No background cleanup is enabled by changing these preferences.

## Boundaries

- No microphone, recording, automatic insertion, History access, or Vocabulary writes.
- No credentials are passed in the prompt. Codex handles its own existing login.
- The subprocess receives an allowlisted environment, an isolated temporary
  working directory, and no user config or project instructions. Skill instructions and bundled skills are disabled; discovered local skill paths
  are individually disabled so literal `$skill` text cannot inject a skill body. Shell, web,
  browser, computer, plugin, app, hook, and subagent features are disabled. A custom
  permission profile denies all tool filesystem access and command networking,
  including built-in tools that older CLIs still advertise. Strict config parsing
  rejects unsupported options instead of silently ignoring restrictions. This is a dedicated cleanup invocation, not
  an existing interactive Codex conversation.
- The request is supplied through stdin, not shell interpolation or argv. Foil
  parses bounded JSONL stdout in memory and discards stderr because either may echo input. The structured result
  and successful turn completion are validated before display. No raw provider error is shown or logged by Foil.
- Owner-private temporary input/schema/output files are removed on normal
  completion, failure, or cancellation. A process/app crash can leave temporary
  files for OS cleanup. Codex uses ephemeral mode and disables its history
  persistence. Hosted processing remains subject to the user's Codex account.
- The panel retains its input/result only while open. It does not save examples
  or automatically learn corrections. Future learning should compare original,
  local-rule output, agent output, and user-accepted output, with separate consent
  for retained examples and existing Vocabulary authorization for rule changes.

## Acceptance

1. Installed Foil Dev on Mini 2 loads the example and displays the real hosted
   Codex result with Supabase and Vercel, preserving the original meaning.
2. A text example with numbers and negation preserves them. Text resembling
   instructions is treated as dictation, not as an instruction to execute tools.
3. Cancel and timeout stop the native process, remove temporary files, and prevent
   late results from replacing the UI or becoming copyable.
4. Another group's aliases, suppressed globals, and disabled rules are absent
   from requests. Invalid/deleted groups fail before invoking Codex.
5. Unavailable Codex, failed runs, and malformed output preserve the original and
   show an actionable error. No submitted text appears in Foil diagnostics.

Focused tests: `FoilTests/CodexTextCleanupTests` and
`FoilUITests/FoilUITests/testCodexCleanupExampleAndCancellation`, and
`FoilUITests/FoilUITests/testCodexCleanupModelAndInstructionsPersistAcrossRelaunch`. The UI test uses
a deterministic runner only with both `--ui-testing` and `--mock-codex-cleanup`
in Debug builds; installed live QA must omit the mock flag.

Run `python3 scripts/test-codex-cleanup-boundary.py` on a Mac with Codex installed
to verify the actual assembled request and built-in file-tool denial against a
loopback Responses stub. It compiles the production argument builder, injects a
synthetic skill and PNG, and proves the ordinary read-only control can read the
image while the cleanup profile cannot. No hosted inference is used.
