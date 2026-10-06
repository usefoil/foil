# Agent Access

Agent Access lets a local coding agent inspect Foil's allowed Vocabulary fields,
preview exact local corrections, and submit proposals or action requests for
review. It is off by default and works only while Foil is running. A paired
agent can apply Vocabulary edits for one exact app group during a grant lasting
up to one hour or until Foil closes or Agent Access is turned off.

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
Vocabulary, preview a correction set in memory, submit an ordinary proposal or
action request, use a paired grant for scoped edits, and read status. No plugin, skill, MCP registration, helper
installation, or PATH change is required. The agent must be running locally on
the same Mac and able to access your user-owned Unix socket.

## Pair an agent for scoped edits

In **Agent Access -> Agent permissions**, enter a name, choose an enabled Cleanup
Group containing only exact installed app paths, then click **Pair agent and copy
editing prompt**. Paste that prompt into the agent task. It contains a bearer
credential for a grant lasting up to one hour or until Foil closes or Agent
Access is turned off; treat it as
a secret. Foil stores only its hash in the audit file and keeps the active grant
in the running process. Restarting Foil ends the grant, so a saved or forged
grant file cannot create write access.
The agent can check its current scope and expiry with `GET /v1/access` using
`Authorization: Bearer <credential>`.

While the grant is active, the agent may submit a new correction only for that
group to `POST /v1/vocabulary/delegated-proposals`, or edit policy fields on
existing corrections already in that group through
`POST /v1/vocabulary/delegated-actions`. Foil applies the request using the same
validation as its review UI and records it under that agent in the permissions
panel. The agent must poll the ordinary proposal or action status URL until it
reports `applied` or `approved`; HTTP 202 means accepted for processing, not
applied. Repeating the same request ID and content is idempotent.

The grant does not permit a global correction, app routing or group creation,
moving a correction between scopes, global local-corrections toggle, or group
suppression. These still go through the ordinary in-Foil review routes. If
group membership or routing differs from the paired paths, Foil blocks the
grant's requests. Restoring the same routing before expiry makes the grant
usable again. **Revoke** immediately blocks new requests and pending delegated
application. Turning Agent Access off ends paired grants and blocks all connections. Recent delegated
requests remain visible under the paired agent and in the existing proposal or
action records.

## Inspect an exact app target

`POST /v1/vocabulary/targets/verify` accepts one to eight exact installed
`.app` paths. It returns each app's resolved Cleanup Group and whether that
group contains an exact path assignment. With `expected_group_id`, it also
reports whether all supplied apps resolve to that group and whether routing to
the group is exclusive to those requested paths. It never lists other installed
apps. The default Cleanup Group is a fallback for every unassigned app, so it
is never exclusive and this last field is always false for that group.

`POST /v1/vocabulary/effective-preview` accepts one exact app path and caller
supplied `sample_text` (up to 16 KiB UTF-8). Foil resolves the target group and
runs the current local correction rules in memory, returning the output and
applicable global and group rules. The preview respects the current local
corrections switch and does not read History, capture a transcript, or save the
sample. Use a separate proposal preview to validate proposed changes.

## Review a proposal

Open **Agent Access -> Review vocabulary proposals**. You can edit or omit
individual suggestions, reject the proposal, or apply the reviewed corrections.
Applying a proposal creates ordinary Foil Vocabulary entries and exact local rules;
it does not turn on the global **Apply local corrections** switch. That switch and
any Cleanup Group scope remain under your control.

Global exact corrections act as defaults. A rule in the active Cleanup Group
wins when it matches the same phrase; a longer distinct phrase wins over a
shorter match. In Vocabulary settings, use a global correction's **Exceptions**
menu to leave its phrase unchanged in selected Cleanup Groups. Turning a scoped
rule off does not suppress a global rule; an exception is an explicit choice.
Turning a global correction off clears its group exceptions. A proposal for a
phrase already covered by an exception in that group must resolve the exception
before it can be submitted or applied. Disabling a Cleanup Group also clears its
exceptions; group corrections remain off if that group is re-enabled.

## Review agent action requests

An agent can POST a request to `/v1/vocabulary/actions` to ask Foil to apply a
pending proposal, turn local corrections on or off, set an individual
correction's scope, or assign an installed app to an enabled Cleanup Group. An
agent can also request a new group for 1–8 exact installed app paths and request
that an existing pending proposal be rescoped to it. Each ordinary request needs its own
approval. The group request's `group_id` appears in the action response and can
be used for the rescope request after the group is approved. Foil verifies that
the group contains exactly the requested app paths before changing the proposal.
Rescoping changes the original pending proposal in place; it leaves no second
global proposal waiting to be applied. It does not apply the corrections.
Use exact paths when two installed apps share a bundle identifier. A
new request remains pending until you open **Agent Access -> Review agent action
requests** and choose **Approve change** or **Reject**. Foil shows the exact
correction or setting, current state, requested scope, and for app assignments
the resolved application path. Assigning an app changes its whole Cleanup Group
routing, including that group's cleanup settings. The API has no approval route
and ignores any agent claim that you approved a request elsewhere.

For a coordinated change, `set_correction_policies` accepts 1–50 complete
policies in one action. Each policy names an existing correction, its desired
scope (`global` or an enabled Cleanup Group ID), whether its exact rule is on,
whether matching is case sensitive, and any Cleanup Groups excluded from an
enabled global rule. The action can also explicitly set the overall local
corrections switch. Foil shows the current and requested policy for every
correction, then applies the full set in one catalog save after approval. A
changed Vocabulary or Cleanup Group configuration blocks the old request; the
agent must submit a fresh one. A scope-only `set_correction_scope` request
preserves the correction's On/Off state; a newly scoped rule starts Off.

For example, this action asks to enable one existing correction only in an
agent Cleanup Group while leaving the overall local corrections switch as it
is. The agent gets the correction and group IDs from the read endpoints:

```json
{
  "schema_version": 1,
  "request_id": "scope-codex-correction-1",
  "action": "set_correction_policies",
  "correction_policies": [{
    "correction_id": "<existing correction UUID>",
    "scope_id": "<enabled Cleanup Group UUID>",
    "enabled": true,
    "case_sensitive": false,
    "suppressed_group_ids": []
  }]
}
```

An exact app bundle match takes precedence over a path or display-name match,
including when the bundle is explicitly assigned to the default group.
Cleanup Group order breaks ties between non-default groups; the default group
remains the fallback for equally specific matches.

Requests use a unique `request_id`. Retrying identical content returns the
existing status; reusing an ID with different content fails. Foil stores the
request and decision in an owner-only local audit file. If approval cannot
complete because the target changed or current validation rejects it, Foil
keeps the approval as `approved_pending_apply` and shows the reason. You can
retry after resolving it or stop retrying; stopping does not undo a change
that may already have applied.
An ordinary Vocabulary proposal still needs its own in-Foil review, either in
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
