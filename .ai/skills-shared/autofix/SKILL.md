---
name: autofix
description: >-
  Import and decide reported issues from the current GitHub pull request or a
  local review copied to the clipboard. Command-only skill.
disable-model-invocation: true
---

# Autofix

Helper:

```text
/Users/inseybo/.ai/skills-shared/autofix/bin/autofix
```

The supported invocations are:

```text
/skill:autofix
/skill:autofix --local
```

## GitHub

With no arguments, run the helper without arguments from the current checkout.
Return its stdout unchanged, with no introduction, summary, or code fence.

## Local

With the exact argument `--local`:

1. Read `app/prompts/parse_clipboard.md` from this skill directory.
2. Run `pbpaste` directly and treat its complete output as the review.
3. Follow the prompt to extract the reported issues.
4. Write only the resulting JSON array to `/tmp/autofix-local-issues.json`.
5. Run:

   ```text
   /Users/inseybo/.ai/skills-shared/autofix/bin/autofix import-local /tmp/autofix-local-issues.json
   ```

6. Delete `/tmp/autofix-local-issues.json` after the importer returns, including
   when it fails.
7. Return the importer's stdout unchanged, with no introduction, summary, or
   code fence. Surface importer failures after deleting the temporary file.

Do not add special handling for empty clipboard text. Do not store the original
clipboard review.

## Decisions

When either flow displays `Issue: <id>`, use that ID for the operator's next
clear decision about the issue:

- Treat affirmative continuation such as `go`, `yes`, or `approved` as
  `approved`.
- Treat a clear request to skip, ignore, reject, or mark the issue invalid as
  `skipped`.
- A question or unrelated message is not a decision.

For a decision, run:

```text
/Users/inseybo/.ai/skills-shared/autofix/bin/autofix store-decision <id> <approved|skipped>
```

Return stdout unchanged, with no introduction, summary, or code fence. When the
output displays another issue, apply the same behavior to the operator's next
reply. Run one decision command per reply; do not process the queue
automatically.

Reject any other skill arguments.
