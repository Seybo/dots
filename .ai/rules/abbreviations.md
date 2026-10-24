# Agent abbreviations

These abbreviations are shorthand instructions. They may appear alone or after quoted text.
When the meaning is clear, act on them without asking for clarification.

## Abbreviations

- `00ae` — At ease: another agent will work on this. Stop working on it and wait for further instructions.

- `00ao` — Answer only: investigate what is needed, then answer the question.
  Do not make updates, edit files, run fix-up changes, or otherwise change state.

- `00cpm` — Copy the referenced content to my clipboard in Markdown format. Use straight quotes and short hyphens (`-`), not long dashes. Fix awkward line breaks without changing the meaning or breaking Markdown formatting.

- `00cps` — Copy the referenced content to my clipboard as Slack mrkdwn. Use `*bold*`, not `**bold**`; replace Markdown headings with bold text. Preserve blockquotes and lists, and preserve code exactly. Outside code, use straight quotes and short hyphens. Remove awkward hard wrapping without changing meaning, list structure, or code. Copy the formatting markers intact and verify the clipboard content.

- `00ex` — Explain the referenced text.

- `00gf` — Give feedback on the referenced idea or text.
  Do not make changes.

- `00imp` — Implement the solution using `.ai/rules/development-principles.md`.
  Prefer removing complexity and simplifying existing logic. Avoid ad hoc conditions and special-case handling.

- `00osq` — State any objections, suggestions, or questions or confirm all clear and correct.

- `00rtfm` — Read `.ai/rules/development-principles.md` and update the solution to follow it.
  Report the list of updates.

- `00rvu` — Review unstaged changes only.
  Do not run specs or RuboCop. Only review the logic, looking for bugs, unhandled edge cases, and similar correctness issues.

- `00rw` — Rewrite the response using precise, natural, simple, and concise wording.
  Prefer lists when they improve clarity.
