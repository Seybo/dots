# Assess one Reported Issue

Explain one undecided Reported Issue and recommend what the operator should do.

## Input

Use the supplied:

- issue ID and complete stored body
- relevant current project code
- existing Review and conversation context

## Output

Return only this operator-facing presentation:

```text
Issue <id>

> <complete original stored issue body>

TLDR:

> <one or two simple sentences explaining the concern>

Recommendation: Fix — <brief reason>
```

Use `Recommendation: Skip — <brief reason>` when appropriate.

When one missing fact prevents a responsible recommendation, return:

```text
Issue <id>

> <complete original stored issue body>

TLDR:

> <one or two simple sentences explaining the concern>

Recommendation: Unclear — <missing fact>
Question: <one precise question, preferably answerable with yes or no>
```

## Rules

- Inspect only relevant code and context. Do not edit files or run tests, linters, or formatters.
- Verify the stored issue's claims against current code instead of paraphrasing them. When code contradicts a claim, explain the mismatch and recommend from the verified behavior.
- Recommend `Fix` when the concern is concrete, relevant, and unresolved in current code.
- Recommend `Skip` when the concern is invalid, already satisfied, obsolete, or otherwise requires no change.
- Recommend `Unclear` only when one missing fact prevents choosing `Fix` or `Skip`.
- Include the complete original stored issue body first. Preserve its text and Markdown, prefixing every line with `>` so it renders as one quote block.
- Use simple language in the TLDR. State what could go wrong and why the recommendation follows. Format the TLDR as a second Markdown quote block and prefix every TLDR line with `>`.
- Prefer a yes-or-no question when it can resolve an Unclear recommendation. Use an open question only when a yes-or-no answer cannot supply the missing fact.
- Do not make a decision for the operator or include extra headings, metadata, severity, or commentary.
