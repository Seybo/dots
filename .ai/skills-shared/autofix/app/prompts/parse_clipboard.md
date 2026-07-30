# Parse clipboard review

Turn the clipboard review into reported issues.

Rules:

- Extract every concrete concern reported by the reviewer.
- Keep a concern even when it may be invalid; the operator decides that later.
- Ignore praise, summaries, conclusions, and other text that does not report a concern.
- Rewrite each issue into a concise, self-contained body.
- Preserve the reported meaning, evidence, file paths, symbols, code references, and failure conditions.
- Do not invent evidence or implementation requirements.

Write a JSON array containing one non-empty string per issue, in source order:

```json
[
  "First issue.",
  "Second issue."
]
```

Write `[]` when the review reports no concerns. Do not add keys, metadata, or explanatory text.
