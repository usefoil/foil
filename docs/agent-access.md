# Agent Access

Agent Access lets a local coding agent inspect Foil's allowed Vocabulary fields,
preview exact local corrections, and submit proposals or action requests for
review. It is off by default and works only while Foil is running. An agent
cannot approve or directly apply a change.

## Connect a local agent

1. Choose **Open Foil** from the menu bar, then **Agent Access** in the sidebar.
2. Turn on **Allow local agents to access Vocabulary** and wait for **Running**.
3. Click **Copy prompt for local agent**.
4. Paste the prompt into a fresh local Codex task, add your Vocabulary request,
   and let the agent read and follow the returned instructions.

The Agent Access page labels the local service as Off, Starting, Running, or
unable to start. The sidebar shows an indicator while it is starting, running,
or in error. **Running** means Foil is ready to accept local connections; it
does not mean an agent has connected. If the service fails to start, Foil turns
access off, shows the error, and offers **Try again** after you resolve it. If
Foil cannot load the service itself, restart after updating or repairing the
app. The sidebar also shows a count when proposals are waiting for review, even
while access is off.

The production command has this stable shape:

```sh
/usr/bin/curl --silent --show-error --connect-timeout 1 --max-time 12 \
  --retry 10 --retry-all-errors --retry-delay 1 \
  --unix-socket "$HOME/Library/Application Support/Foil/agent-v1.sock" \
  http://foil/v1/instructions
```

The copied prompt includes brief Foil context and the command above. Copy it
from Foil instead of typing it when possible. Foil Dev uses its own `Foil Dev`
Application Support directory, so its copied command points to a different socket.

The instructions response tells the agent how to list available scopes, inspect
Vocabulary, preview a correction set in memory, submit an inert proposal or
action request, and read its status. No plugin, skill, MCP registration, helper
installation, or PATH change is required. The agent must be running locally on
the same Mac and able to access your user-owned Unix socket.

## Review a proposal

Open **Agent Access -> Review vocabulary proposals**. You can edit or omit
individual suggestions, reject the proposal, or apply the reviewed corrections.
Applying a proposal creates ordinary Foil Vocabulary entries and exact local rules;
it does not turn on the global **Apply local corrections** switch. That switch and
any Cleanup Group scope remain under your control.

## Review agent action requests

An agent can POST a request to `/v1/vocabulary/actions` to ask Foil to apply a
pending proposal, turn local corrections on or off, set an individual
correction's scope, or assign an installed app to an enabled Cleanup Group. A
new request remains pending until you open **Agent Access -> Review agent action
requests** and choose **Approve change** or **Reject**. Foil shows the exact
correction or setting, current state, requested scope, and for app assignments
the resolved application path. Assigning an app changes its whole Cleanup Group
routing, including that group's cleanup settings. The API has no approval route
and ignores any agent claim that you approved a request elsewhere.

An exact app bundle match takes precedence over a path or display-name match;
Cleanup Group order breaks ties between matches of the same kind.

Requests use a unique `request_id`. Retrying identical content returns the
existing status; reusing an ID with different content fails. Foil stores the
request and decision in an owner-only local audit file. If approval cannot
complete because the target changed or current validation rejects it, Foil
keeps the approval as `approved_pending_apply` and shows the reason. You can
retry after resolving it or stop retrying; stopping does not undo a change
that may already have applied.
An applied Vocabulary proposal still needs its own in-Foil review, either in
the proposal sheet or through an approved apply request.

For example, a proposal may group `super base` and `Superbase` as spoken forms for
`Supabase`. After review, Foil stores them as separate explicit correction rules.
If you also approve `codecs` -> `Codex` only for an agent Cleanup Group, ordinary
uses of “codecs” in other apps remain unchanged. Foil keeps the provider transcript
available as the original recovery text for the current session.

## Privacy and shutdown

Agent Access exposes only Vocabulary names, terms, corrections, exact-rule
settings, and enabled Cleanup Group identities. It does not expose History,
transcripts, audio, credentials, provider settings, source apps, project files, the
clipboard, or the active application. Request bodies and correction text are not
written to diagnostics.

Turning Agent Access off closes active connections and removes the socket. Already
received proposals and action requests remain in Foil for review, but agents
cannot read their status while access is off. Closing Foil also stops the service.

If the copied command cannot connect, confirm that Foil is open, Agent Access shows
**Running**, and the command came from the same Foil or Foil Dev build you are using.
