# Agent abbreviations

These abbreviations are shorthand instructions. They may appear alone or after quoted text.
When the meaning is clear, act on them without asking for clarification.

## Abbreviations

- `00ex` — Explain the referenced text using simple, precise technical terms.
  Prefer a clear paraphrase, then any necessary context.

- `00gf` — Give feedback on the referenced idea or text.
  Do not make changes. Say whether you agree, disagree, or partially agree, and explain why in simple technical terms.

- `00rar` — Read the new/other agent's latest review file in the task folder.
  Locate the current task folder if needed. In Pi, prefer `claude_review*.md`; in Claude, prefer `pi_review*.md`. Use the newest matching review file unless the user names one, and summarize actionable findings before changing code.

- `00rvu` — Review unstaged changes only.
  Do not run specs or RuboCop. Only review the logic, looking for bugs, unhandled edge cases, and similar correctness issues.
