# Normalize one GitHub issue

Turn one inline pull request comment into one concise, self-contained Reported Issue.

## Input

Use the supplied:

- source ID
- comment body
- path
- current and original line numbers when present
- diff hunk when present
- current code context when the file still exists

## Output

Return only one JSON value.

For a concrete concern, return:

```json
{
  "source_id": "<GitHub comment ID>",
  "body": "<self-contained Markdown concern>"
}
```

If the comment contains no concrete concern, return `null`.

## Rules

- State the problem, relevant evidence or location, and required outcome.
- Preserve enough code context for another agent to act without the raw GitHub response.
- Keep a concrete concern even when its line is outdated, the referenced code was deleted, or the concern appears resolved.
- Describe current evidence without deciding whether the concern is valid. The operator approves or skips it later.
- Do not invent missing context or include credentials.
- Do not include explanation or a Markdown code fence around the JSON.
