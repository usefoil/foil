# Post-transcript Vocabulary suggestions — discussion draft

Status: UX proposal for discussion with the user. Not implemented or approved as
a background feature. This follows the Codex text cleanup experiment and its
saved model, reasoning, instructions, and timing controls.

## Intended outcome

A user can ask the same agent they use for cleanup to help Foil learn recurring
names and transcription mistakes. Useful deterministic corrections should reduce
how often that user needs agent cleanup. The flow should require little navigation
and make the proposed rule and its scope understandable before it takes effect.

Use the user's existing agent integration and account; do not introduce another
LLM service. Keep agent cleanup and learning independently controllable.

## First experiment to discuss

1. Run cleanup on a pasted text sample. Let the user review and edit the cleaned
   result so the experiment has an explicitly accepted version.
2. Offer **Suggest Vocabulary corrections** beside that result. One click sends
   the original and accepted text, plus relevant existing Vocabulary and app/group
   context, to the selected agent. Disclose what will be sent. Nothing is learned
   merely because cleanup ran or its output was copied.
3. Show a compact review inline: `super base → Supabase`, suggested variants,
   sample matches/nonmatches, and exact destination apps or Cleanup Group. Separate
   spelling/name rules from punctuation or style rewrites that should stay in a
   cleanup prompt. Do not propose ambiguous generic words as automatic replacements.
4. Let the user edit, accept selected suggestions together, or dismiss them. Use
   the existing Vocabulary validation, scoping, permissions, idempotency, and audit
   path; show conflicts in place. Avoid a second approval screen for the same action.
5. Test the accepted rules against held-out examples with agent cleanup off. Make
   it easy to find and undo the resulting rule changes.

## Decisions to make together before implementation

- Is learning an explicit button per result, an opt-in suggestion after review,
  or eventually an automatic background analysis mode?
- What counts as accepted text: an explicit acceptance action, edited text, or
  copying? The first experiment proposes explicit acceptance, not inference.
- Should suggestions default to the app that produced the text, its Cleanup Group,
  or ask for scope once? A pasted sample has no trustworthy originating app.
- How should casing, punctuation, word boundaries, and negative examples appear
  without requiring one approval for every variant?
- Which changes need confirmation under existing agent permissions? How should
  a user opt into more autonomy while still seeing and undoing what changed?
- Should examples be discarded with the panel, or can the user separately opt into
  retaining selected examples for recurrence analysis? No History access, audio,
  credential access, or automatic retention is authorized by this draft.
- What should happen when cleanup improves style but reveals no reusable Vocabulary
  rule? The suggested result is “No Vocabulary changes suggested.”

## Evidence needed from the experiment

Use synthetic examples first. Compare original transcription, deterministic local
correction output, agent output, and explicitly accepted text when those stages are
available. Do not invent missing stages. Verify names, numbers, negation, app scope,
conflicts, duplicate/idempotent requests, rejection/undo, and no rule changes after
cancel. Include examples where a name-like phrase must remain ordinary words.

Success means a useful, understandable rule works on another example in its chosen
scope without the agent, and does not change an excluded app or a negative example.
A visually plausible suggestion alone is not enough evidence.
