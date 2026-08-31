# Agent abbreviations

These abbreviations are shorthand instructions. They may appear alone or after quoted text.
When the meaning is clear, act on them without asking for clarification.

## Abbreviations

- `00ao` — Answer only: investigate what is needed, then answer the question.
  Do not make updates, edit files, run fix-up changes, or otherwise change state.

- `00cc` — Copy the referenced content exactly to the system clipboard.
  Do not modify the content or include surrounding commentary.

- `00ex` — Explain the referenced text.

- `00gf` — Give feedback on the referenced idea or text.
  Do not make changes.

- `00imp` — Implement the solution using `.ai/rules/development-principles.md`.
  Prefer removing complexity and simplifying existing logic. Avoid ad hoc conditions and special-case handling.

- `00osq` — Objections? Suggestions? Questions?

- `00rtfm` — Read `.ai/rules/development-principles.md` and update the solution to follow it.
  Report the list of updates.

- `00rvu` — Review unstaged changes only.
  Do not run specs or RuboCop. Only review the logic, looking for bugs, unhandled edge cases, and similar correctness issues.
