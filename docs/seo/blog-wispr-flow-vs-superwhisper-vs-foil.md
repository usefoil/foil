# Wispr Flow Vs Superwhisper Vs Foil

Meta title: Wispr Flow vs Superwhisper vs Foil: Mac Dictation Compared

Meta description: Compare Wispr Flow, Superwhisper, and Foil for Mac dictation, local transcription, provider choice, privacy tradeoffs, paste recovery, and iOS expectations.

Canonical: https://mean-weasel.github.io/foil/blog/wispr-flow-vs-superwhisper-vs-foil/

Target queries:

- wispr flow vs superwhisper
- wispr flow vs superwhisper vs foil
- superwhisper alternative mac
- wispr flow alternative mac
- mac dictation app comparison
- local dictation app mac

## Draft

Wispr Flow, Superwhisper, and Foil all start from the same user desire: speak
instead of type. The differences show up when you ask where transcription runs,
how much control you get, what happens when paste fails, and whether mobile
dictation is part of the promise.

The short version:

- Wispr Flow is the best fit when you want a polished, cross-platform dictation
  and AI writing layer.
- Superwhisper is the best fit when you want a mature local-first tool with a
  power-user mode system.
- Foil is the best fit when you want Mac-first dictation with explicit provider
  choice, local transcription as an option, optional cleanup, and visible
  recovery when paste does not land.

Foil is not trying to pretend the other tools are bad. The useful question is
which tradeoff you want.

## Comparison Table

| Category | Wispr Flow | Superwhisper | Foil |
| --- | --- | --- | --- |
| Best fit | Cross-platform AI dictation and rewriting | Local-first dictation for power users | Mac-first dictation with provider control |
| Local transcription | Cloud-first voice transcription | Local models are central to the product | Local whisper.cpp via localhost is supported |
| Hosted provider choice | Wispr-managed service path | Product-managed cloud features and local models | Local, Groq, OpenAI, or custom OpenAI-compatible endpoints |
| Cleanup/rewrite | Integrated AI writing layer | Modes and workflows can transform dictation | Optional cleanup with raw transcript fallback |
| Failure recovery | Product-specific history and retry flows | History and local recordings | History, copy, paste, edit, export, retry, and clipboard fallback |
| Privacy posture | Privacy Mode and retention controls, still server-processed for transcription | Local processing with local recording/history behavior to understand | Route-explicit: local when local, hosted when hosted |
| iOS expectations | Public iOS app | Public iOS app | Closed iPhone preview; custom keyboard, Full Access, and verified host-app rows only |
| Best reason to choose it | You want polished cross-platform voice writing | You want a powerful local dictation environment | You want explicit Mac provider routing and recoverability |

## Why People Compare Wispr Flow And Superwhisper

Wispr Flow made AI dictation feel mainstream: hold a key, speak naturally, and
get cleaner text back. Its advantage is polish and breadth. The tradeoff is that
voice transcription depends on Wispr's service path and internet connectivity.
Wispr's own help center says Flow requires internet connectivity for voice
transcription, and its support docs cover VPN, proxy, security-tool, and
connection-loss cases.

Superwhisper appeals to a different user. It is local-first, powerful, and
designed for people who want control. The tradeoff is that power can become
configuration overhead. Users evaluating it should also understand its history
and recording behavior, because Superwhisper docs describe recordings and
metadata stored locally by default.

Foil sits between those poles. It is not a full cross-platform writing layer,
and it is not trying to maximize modes. It is a Mac dictation app built around a
simple pipeline: capture audio, choose a transcription route, optionally clean
up the text, paste into the active app, and preserve the result if delivery
does not work.

## Local, Hosted, Or Custom: The Provider Question

For many users, the real search is not "which dictation app is coolest?" It is
"where does my voice go?"

Wispr Flow is cloud-first. That can be excellent when the service path is fast,
available, and allowed by your network.

Superwhisper is local-first. That can be excellent when you want on-device
processing and are comfortable with its configuration model.

Foil makes the provider route visible. You can use local whisper.cpp through a
localhost OpenAI-compatible server, hosted Groq Whisper, OpenAI Whisper, or a
custom OpenAI-compatible endpoint. That makes Foil useful for people who want a
local baseline but still want hosted speed or their own infrastructure when it
makes sense.

The important wording is "route." Local transcription, hosted transcription,
and hosted cleanup are different privacy and reliability choices. A good Mac
dictation setup should say which one it is using.

## Paste Recovery Matters More Than Comparison Tables Admit

Most comparison pages focus on accuracy and price. Those matter, but a
dictation tool can transcribe perfectly and still feel broken if the text does
not land in the target app.

That is why paste recovery is a core Foil theme. Foil separates the stages:
recording, transcription, optional cleanup, insertion, clipboard fallback, and
history. If cleanup fails after transcription succeeds, the raw transcript
should still be available. If paste does not land, the thought should not
disappear.

No Mac dictation app can honestly promise perfect insertion into every target.
The better product promise is narrower and more useful: make the delivery state
visible and keep the transcript recoverable.

## What About iOS?

iOS is where dictation promises get tricky. Keyboard extensions, secure fields,
host-app behavior, app switching, permissions, background capture, and state
reset can all affect whether text lands where the user expects.

Wispr Flow and Superwhisper both have public iOS apps. Foil's iOS work is a
closed iPhone preview today. It uses a custom keyboard, requires Allow Full
Access, and should only be described through verified host-app rows: Notes,
Safari normal text fields, and Messages fake-recipient draft insertion without
sending. Mail is deferred, and secure fields should reject the custom keyboard.

That evidence can become a product advantage. "Verified here, limited there" is
more trustworthy than vague "works everywhere" copy.

## Which One Should You Choose?

Choose Wispr Flow if you want a polished cross-platform AI dictation layer and
you are comfortable with a cloud-first transcription path.

Choose Superwhisper if you want a mature local-first dictation tool and you are
comfortable with deeper configuration, modes, and local history behavior.

Choose Foil if you mainly dictate on a Mac, want provider choice to be explicit,
want local transcription available, and care about recovery when paste or
cleanup fails.

For many people, the right answer is not permanent. Try the app that matches
your current constraint: polish, local power, or route control.

## Keep Reading

- Wispr Flow alternative for Mac
- Does Wispr Flow work offline?
- Wispr Flow not pasting text?

## Sources

- Wispr Flow: What is Flow?
  https://docs.wisprflow.ai/articles/2772472373-what-is-flow
- Wispr Flow: VPN, proxy, security-tool, and connection-loss cases
  https://docs.wisprflow.ai/articles/3834764683-why-vpns-or-security-tools-can-block-wispr-flow
- Wispr Flow status history
  https://statuspage.incident.io/wispr-flow/history
- Wispr Flow privacy
  https://wisprflow.ai/privacy
- Superwhisper Pro
  https://superwhisper.com/docs/get-started/sw-pro
- Superwhisper history management
  https://superwhisper.com/docs/get-started/history-management
- Superwhisper sensitive data
  https://superwhisper.com/docs/security/sensitive-data
