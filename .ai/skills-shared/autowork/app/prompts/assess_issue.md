# Assess one Reported Issue

Explain one undecided Reported Issue and recommend what the operator should do.

## Input

Use the supplied:

- issue ID and complete stored body
- relevant current project code
- existing Review or Task and conversation context

## Output

Return only this operator-facing presentation:

```text
[MM_NTF] Issue <id>

> <complete original stored issue body>

TLDR:

> <one or two simple sentences explaining the concern>

Recommendation: Fix — <one concise, factual, self-contained sentence>
```

Use `Recommendation: Skip — <one concise, factual, self-contained sentence>`
when appropriate.

When one missing fact prevents a responsible recommendation, return:

```text
[MM_NTF] Issue <id>

> <complete original stored issue body>

TLDR:

> <one or two simple sentences explaining the concern>

Recommendation: Unclear — <missing fact>
Question: <one precise question, preferably answerable with yes or no>
```

## Rules

- Begin every assessment with the exact prefix `[MM_NTF]` as shown above.
- Inspect only relevant code and context. Do not edit files or run tests, linters, or formatters.
- Verify the stored issue's claims against current code instead of paraphrasing them. When code contradicts a claim, explain the mismatch and recommend from the verified behavior.
- Recommend `Fix` when the concern is concrete, relevant, and unresolved in current code.
- Recommend `Skip` when the concern is invalid, already satisfied, obsolete, or otherwise requires no change.
- Recommend `Unclear` only when one missing fact prevents choosing `Fix` or `Skip`.
- The Fix or Skip reason becomes the durable decision reason when the operator accepts the recommendation. Make it factual and understandable later without the current conversation.
- Do not add a category, tag, score, or future prompt lesson to the reason.
- Include the complete original stored issue body first. Preserve its text and Markdown, prefixing every line with `>` so it renders as one quote block.
- Use simple language in the TLDR. State what could go wrong and why the recommendation follows. Format the TLDR as a second Markdown quote block and prefix every TLDR line with `>`.
- Prefer a yes-or-no question when it can resolve an Unclear recommendation. Use an open question only when a yes-or-no answer cannot supply the missing fact.
- Do not make a decision for the operator or include extra headings, metadata, severity, or commentary.
