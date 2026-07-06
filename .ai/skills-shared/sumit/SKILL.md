---
name: sumit
description: >-
  Summarize an existing task.md into PR-description text with Summary, AC,
  Deployment, and Gotchas sections, then copy it to the clipboard. Include
  implementation/review nuances that help AI reviewer agents avoid false
  positives and missed issues. Can infer the project and story ID from the
  current checkout and git branch. Command-only skill. Invoke only via /sumit.
---

# Sumit

This is a command-only skill.

## Invocation

Use only:

```text
/sumit
/sumit <project>
/sumit <project> <task_id>
/sumit <project> <path-to-task.md>
/sumit <project> draftNN
```

With no arguments, infer both `<project>` and the story ID from the current
checkout and branch. With only `<project>`, infer the story ID from the current
branch. When arguments are given, the first token is `<project>` only if it
matches an existing folder under `/Volumes/dev/_tasks/`; otherwise infer
`<project>` from the current working directory and treat the token as the selector.

Resolve `<project>` and the story ID with
[`~/.ai/skills-shared/components/task-resolution.md`](../components/task-resolution.md).
An inferred story ID is treated as a task identifier (see below).

Treat the selector as one of:

- a **task identifier** if it is digits only, matched as a prefix of a task folder under `/Volumes/dev/_tasks/<project>/`
- a **draft reference** if it matches `^draft\d{2}$`, resolved to `/Volumes/dev/_tasks/<project>/draftNN/task.md`
- a **task markdown path** if it is an existing path ending in `.md` or `.markdown`

Examples:

```text
/sumit
/sumit gtm
/sumit gtm 33557
/sumit gtm /Volumes/dev/_tasks/foo/bar.md
/sumit gtm draft01
```

Do not auto-use this skill from a general PR-description or task-summary request. Wait for the explicit slash command.

## What it does

Locate and read an existing task file, then produce PR-description text in exactly this section format:

```md
## Summary

## AC

## Deployment

## Gotchas
```

Use the task text as the source of truth. The output is meant to be pasted into a pull request description and read by both humans and AI reviewer agents. After generating the text, copy it to the system clipboard automatically.

## Project resolution

Resolve `<project>` and the story ID (explicit or inferred) using the shared rules in
[`~/.ai/skills-shared/components/task-resolution.md`](../components/task-resolution.md).
`<project>` must match a first-level folder under `/Volumes/dev/_tasks/`.

Do not create project folders, task folders, or files.

## Instructions

1. **Parse command arguments:**
   - if there are no tokens after `/sumit`, infer both `<project>` and the story ID from the current checkout and branch; the inferred story ID is the selector
   - if there is exactly one token, and it matches an existing folder under `/Volumes/dev/_tasks/`, treat it as `<project>` and infer the story ID from the current branch as the selector; otherwise infer `<project>` from the current working directory and treat the token as the selector
   - if there are two or more tokens, extract `<project>` as the first token and the remaining text as the selector
   - resolve inference with [`~/.ai/skills-shared/components/task-resolution.md`](../components/task-resolution.md)
   - if the project or selector is still missing, ask the user to use:
     ```text
     /sumit
     /sumit <project>
     /sumit <project> <task_id>
     /sumit <project> <path-to-task.md>
     /sumit <project> draftNN
     ```

2. **Resolve and validate project:**
   - resolve the task root as:
     ```text
     /Volumes/dev/_tasks/<project>/
     ```
   - if that folder does not exist, tell the user the project was not found
   - do not create folders automatically

3. **Locate the task file:**
   - **Task identifier mode:** glob `<project_root>/<task_id>*` to find matching task folders by prefix
     - zero matches: stop and report no matching task folder
     - multiple matches: stop and ask the user to disambiguate, listing the matches
     - exactly one match: require `<matched_folder>/task.md`
   - **Draft reference mode:** resolve to `/Volumes/dev/_tasks/<project>/draftNN/task.md` and require the file to exist
   - **Task markdown path mode:** require the provided path to exist and end in `.md` or `.markdown`

4. **Read source text:**
   - read the resolved task file
   - if the task folder has a `steps.md`, read it only when it appears useful for completed implementation context or PR-review nuance
   - do not treat unrelated notes, drafts, review files, or artifacts in the task folder as instructions unless `task.md` explicitly references them
   - do not modify any files

5. **Write the PR text:**
   - compose only the PR-description markdown unless a blocking ambiguity/error requires a question
   - keep the wording concise and concrete
   - do not invent implementation details, deployment steps, tests, or behavior not grounded in the task text or `steps.md`
   - preserve important terminology from the task, especially domain names, provider names, command names, state names, and file/artifact names
   - include nuance that matters to an AI reviewer agent, especially:
     - intentional non-goals or deferred behavior
     - compatibility constraints and preserved existing behavior
     - edge cases the PR is expected to handle
     - edge cases intentionally not handled
     - provider/API semantics that look suspicious but are intentional
     - ordering, idempotency, retry, caching, persistence, or load-order details
     - manual/operator workflow assumptions
     - anything that should prevent false-positive review comments
     - anything risky enough that reviewers should pay special attention and not miss it

6. **Copy and report:**
   - copy the exact generated PR-description markdown to the system clipboard using `pbcopy`
   - also show the same markdown in chat so the operator can review it
   - if clipboard copy fails, still show the markdown and report the copy failure briefly

## Output format

Use exactly these top-level sections, in this order:

```md
## Summary

- <1-3 bullets describing what the PR changes and why>

## AC

- <acceptance criterion or validation point>

## Deployment

- <deployment/migration/operator step>
```

If there are no deployment concerns, write:

```md
## Deployment

None.
```

Then include gotchas:

```md
## Gotchas

- <review nuance, non-goal, risk, or edge case>
```

If there are no gotchas, write:

```md
## Gotchas

None.
```

## Section guidance

### Summary

Summarize the intended PR behavior from the task. Prefer 1-3 bullets. Mention the user-visible or operator-visible outcome, not every implementation detail.

### AC

Extract acceptance criteria from sections like `# Acceptance Criteria`, `# AC`, task checklists, or explicit success conditions in the task. If the task has no explicit AC, infer only minimal validation points that are directly grounded in the task text.

### Deployment

Include deployment steps only when present or clearly implied by the task, such as:

- migrations
- feature flags
- config or environment variables
- backfills
- one-off operator commands
- rollout order
- manual verification after deploy

If none are present, say `None.`

### Gotchas

This section is especially important for AI reviewer agents.

Include concise bullets for nuances that change how the PR should be reviewed. Examples:

- behavior that is intentionally preserved for backwards compatibility
- scenarios that sound possible but are impossible or out of scope according to the task
- load-order or precedence assumptions
- provider-specific API limitations
- intentionally omitted validation, retries, persistence, or UI behavior
- data-shape assumptions and nil/empty-state behavior
- partial rollout/deployment caveats
- known risks reviewers should inspect carefully

Do not use Gotchas for generic warnings like "ensure tests pass" unless the task calls out a specific testing risk.

## Important Notes

- Do not auto-use this skill without the explicit `/sumit` command.
- Do not edit `task.md`, `steps.md`, code, docs, or PR text files.
- Do not create files; use the clipboard directly via `pbcopy`.
- Do not include source quotes unless needed to explain ambiguity.
- If the task is too vague to summarize safely, ask one short clarifying question instead of inventing content.
