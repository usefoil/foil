# Agent Access

Agent Access lets a local coding agent inspect Foil's allowed Vocabulary fields,
preview exact local corrections, and submit a proposal for review. It is off by
default, works only while Foil is running, and has no operation that can apply a
proposal.

## Connect a local agent

1. Open **Foil -> Settings -> General**.
2. Turn on **Allow local agents to access Vocabulary** and wait for **Running**.
3. Click **Copy agent instructions command**.
4. Paste that command into a fresh local Codex task and ask it to follow the
   returned instructions.

The production command has this stable shape:

```sh
/usr/bin/curl --silent --show-error --connect-timeout 1 --max-time 12 \
  --retry 10 --retry-all-errors --retry-delay 1 \
  --unix-socket "$HOME/Library/Application Support/Foil/agent-v1.sock" \
  http://foil/v1/instructions
```

Copy the command from Foil instead of typing it when possible. Foil Dev uses its
own `Foil Dev` Application Support directory, so its copied command points to a
different socket.

The instructions response tells the agent how to list available scopes, inspect
Vocabulary, preview a correction set in memory, submit an inert proposal, and read
the proposal's status. No plugin, skill, MCP registration, helper installation, or
PATH change is required. The agent must be running locally on the same Mac and able
to access your user-owned Unix socket.

## Review a proposal

Open **Settings -> General -> Review vocabulary proposals**. You can edit or omit
individual suggestions, reject the proposal, or apply the reviewed corrections.
Applying a proposal creates ordinary Foil Vocabulary entries and exact local rules;
it does not turn on the global **Apply local corrections** switch. That switch and
any Cleanup Group scope remain under your control.

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
received proposals remain in Foil so you can review or discard them, but agents
cannot read their status while access is off. Closing Foil also stops the service.

If the copied command cannot connect, confirm that Foil is open, Agent Access shows
**Running**, and the command came from the same Foil or Foil Dev build you are using.

