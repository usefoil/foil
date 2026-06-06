# Dictation Dissatisfaction Product Implications

Date: 2026-06-06

Related research:

- `docs/research/dictation-competitor-dissatisfaction-2026-06-06.md`
- `docs/seo/wispr-flow-fanout-map.md`

Purpose:

Use observed dissatisfaction with Wispr Flow and Superwhisper to inform Foil
product decisions, QA proof, support copy, and SEO messaging. This is not a
commitment to copy competitors. It is a map of user pain that Foil can solve or
avoid.

## Product Principles From The Research

### 1. Treat Dictation As A Pipeline, Not A Single Success State

Users experience "dictation failed" when any of these fail:

- microphone capture
- transcription provider route
- cleanup/rewrite
- target app insertion
- clipboard fallback
- history recovery
- state reset after insertion

Product implication:

- UI, diagnostics, tests, and support copy should name the stage that failed.
- A "success" receipt should prove that text reached the target app, or clearly
  state which fallback preserved it.

Existing Foil alignment:

- macOS already distinguishes raw transcription, cleanup fallback, history, and
  paste recovery.
- iOS goal work already emphasizes insertion matrices and consumed/reset state.

### 2. Make Provider Choice A First-Class UX, Not An Advanced Escape Hatch

Observed pain:

- Wispr Flow cloud incidents create a need for alternate routes.
- Users search for local/offline alternatives when network, privacy, or
  availability matter.
- Superwhisper users value local processing but may not want deep
  configuration.

Product implication:

- Keep local whisper.cpp, Groq, OpenAI, and custom OpenAI-compatible routes
  visible and testable.
- Provider setup should show what leaves the machine, what stays local, and
  whether cleanup is enabled.
- Health checks should be route-specific.

Potential feature ideas:

- Provider health summary in Settings.
- "Test this route" button per provider.
- Clear route receipt after transcription: local, Groq, OpenAI, or custom.
- Exportable privacy/route summary for users deciding between tools.

### 3. Recovery Is A Feature, Not A Fallback Footnote

Observed pain:

- Users complain when a transcript exists in history but does not paste.
- Mobile users experience app switching or keyboard-extension failures as
  product failure even if transcription succeeded.

Product implication:

- History should stay fast, searchable, and obvious.
- Last-result recovery should be visible from the menu bar and iOS keyboard/app.
- Retry/paste/copy/edit/export should be core workflows, not hidden utilities.

Potential feature ideas:

- "Last transcript preserved" status when paste fails.
- Per-transcript delivery receipt: pasted, clipboard fallback, copied, failed,
  target app unknown.
- On iOS, explicit state labels: ready, recording, transcribed, inserted,
  consumed, blocked by secure field, needs Full Access.

### 4. Be Conservative With iOS Claims

Observed pain:

- Wispr Flow and Superwhisper both show recurring mobile/iOS complaint
  language: keyboard bugs, app switching, sign-in, crashes, action button
  failures, paste not landing, and transcript/history mismatch.

Foil context:

- Foil iOS is actively in progress.
- Existing goal docs are already building the right proof base: onboarding,
  Full Access health, insertion matrices, secure-field behavior, physical-device
  receipts, and consumed/reset state.

Product implication:

- Public iOS messaging should say what is verified, not what is hoped.
- Maintain a host-app insertion matrix and publish it when useful.
- Treat secure-field rejection and platform-limited targets as expected
  behavior, not bugs to hide.

Potential feature ideas:

- In-app iOS compatibility matrix generated from QA evidence.
- "Why the keyboard cannot appear here" copy for secure fields.
- One-tap diagnostics export without transcript/audio content.
- Clear Full Access explanation that distinguishes insertion mechanics from
  privacy.

### 5. Avoid Surprise Retention

Observed pain:

- Superwhisper docs say recordings/metadata are saved locally by default.
- Users are sensitive to both cloud retention and local recording trails.
- Wispr Flow Privacy Mode creates a distinction between zero retention and
  server-side processing that many users may not understand.

Product implication:

- Foil should continue making audio lifecycle, transcript history, diagnostics,
  and clipboard behavior explicit.
- Retention settings should be easy to find and easy to explain.

Potential feature ideas:

- First-run "where your data goes" summary.
- Retention quick controls: keep history, limit history, off.
- Local audio retry policy shown next to provider settings.
- Periodic privacy audit in QA: secret scan, transcript log scan, diagnostics
  redaction check.

### 6. Keep Pricing And Packaging Boring

Observed pain:

- Search and community language around Wispr Flow and Superwhisper includes
  pricing anxiety: subscription cost, lifetime cost, free alternatives, student
  discounts, "worth it", and surprise plan friction.

Product implication:

- If Foil introduces paid plans, make the plan boundaries boring and predictable.
- Do not gate recovery, export, or privacy-critical features in ways that make
  the app feel unreliable after payment.

Potential packaging principle:

- Core dictation reliability and transcript recovery should feel like table
  stakes, not upsells.

## SEO And Messaging Implications

Good angles:

- Wispr Flow vs Superwhisper vs Foil
- Superwhisper alternative for Mac
- Wispr Flow Privacy Mode vs local dictation
- Why Mac dictation apps fail to paste text
- Local dictation without Superwhisper
- iOS dictation keyboard reliability: what can and cannot be guaranteed

Good copy primitives:

- "Choose your transcription route."
- "Local when you need control; hosted when you want speed."
- "Recover the transcript when paste does not land."
- "Foil is explicit about where text goes."
- "Verified host-app behavior beats vague 'works everywhere' claims."

Claims to avoid:

- Works in every app.
- Fully offline in every configuration.
- Private by default.
- No paste failures.
- iOS keyboard works everywhere.
- Better than Wispr Flow/Superwhisper for every user.

## QA Implications

Strongest product failure modes to keep testing:

- Transcription succeeds but paste/insertion fails silently.
- Cleanup fails and raw transcript is lost.
- Provider route is not the one the UI claims.
- History says a transcript exists but copy/paste/retry does not work.
- iOS keyboard inserts stale text or inserts the same transcript twice.
- iOS secure field prevents keyboard use but Foil preserves stale pending state.
- Diagnostics accidentally include transcript text, API keys, clipboard
  content, or raw audio paths that reveal sensitive material.

Evidence types that match these risks:

- macOS cross-app paste smoke.
- Provider QA route tests.
- Diagnostics log inspection.
- iOS physical-device host-app matrix.
- WDA source confirming inserted text count and consumed state.
- App Group snapshot showing idle/no transcript after insertion.
- Secret/transcript grep over logs and exported diagnostics.

## Near-Term Product Questions

1. Should Foil publish an explicit "where your dictation goes" screen before
   iOS launch?
2. Should the macOS menu bar show the current provider route more prominently?
3. Should paste failures create a visible "transcript preserved" receipt?
4. Should iOS launch with a public compatibility matrix instead of broad
   keyboard claims?
5. Should history retention defaults be revisited before SEO content drives
   privacy-sensitive users to the app?
6. Should we build a simple "compare my setup" page for local vs hosted vs
   custom provider routes?
