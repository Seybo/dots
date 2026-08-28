---
description: Generate a PR description from a task.md under $DEV_ROOT/_tasks/shaka_gtm. Finds the task folder by id prefix and writes a Codex-review-friendly description with the repo's mandatory PR sections.
---

# /pr-description-from-task

## User arguments

$ARGUMENTS

Generate a PR description from a GTM task file. The output is meant for a Codex AI reviewer: include the context it cannot safely infer from the diff, do not drop important task constraints, and do not invite false positives.

## Invocation

- `/pr-description-from-task` — infer `<task_id>` from the current gtm branch
- `/pr-description-from-task <task_id>` — find `$DEV_ROOT/_tasks/shaka_gtm/<task_id>*/task.md`

Examples:

- `/pr-description-from-task`
- `/pr-description-from-task 33419`
- `/pr-description-from-task 33357`

`task_id` must be a non-empty token. It is matched as the start of a task folder name under `$DEV_ROOT/_tasks/shaka_gtm/` (the task root for the registered `shaka_gtm` project in `~/.ai/skills-shared/components/projects.yml`), the same prefix style used by `/workit`. When it is omitted, infer the Shortcut story ID from the current branch using the canonical `sc-<digits>` regex in `~/.ai/skills-shared/components/task-resolution.md` and use it as `<task_id>`.

## Procedure

1. Parse `$ARGUMENTS` as `<task_id>`.
   - If missing, infer it from the current branch's `sc-<digits>` segment using `~/.ai/skills-shared/components/task-resolution.md`. Only if no story ID can be inferred, ask the user to run:
     ```text
     /pr-description-from-task <task_id>
     ```
   - Treat it as a folder-name prefix, not necessarily digits-only. This supports folders like `33419-*` and timestamp/manual task folders.
2. Resolve the task folder:
   - Search exactly:
     ```text
     $DEV_ROOT/_tasks/shaka_gtm/<task_id>*
     ```
   - Expected: exactly one directory.
   - If none, report no task folder found.
   - If multiple, list matches and ask the user to disambiguate.
   - Require `task.md` inside the matched folder.
3. Read the full `task.md`.
4. Extract the PR description from `task.md` only, with these priorities:
   - Goal / why this task exists.
   - Operator flow and command interface.
   - Acceptance criteria and concrete verification behavior.
   - Safety rules and intentional trade-offs.
   - Data integrity / privacy constraints.
   - Reconciliation notes, especially scope drift that reviewers should not flag if it is intentional.
   - Deployment context, including explicit “not a problem” notes such as empty production DB / safe local DB recreation.
5. Do **not** dump the whole task. Compress it.
6. Do **not** add generic diff summaries Codex can infer by reading the PR.
7. Do **not** omit important caveats just because they do not fit the three mandatory sections; add extra sections after the mandatory ones.
8. Do **not** invent verification or QA that is absent from `task.md`. If the task has no manual QA notes, omit the Manual QA section or say only what is checkable from AC.
9. If `task.md` conflicts with the current diff or current docs and the conflict is obvious from the task text alone (for example, an outdated field-write block and a later reconciliation note), prefer the latest/reconciled task section and mention the reconciliation in Review notes. Do not silently preserve stale task text.

## Required output format

Return one Markdown code block only:

````text
```markdown
## Summary
<!-- What changed and why, in 2–4 sentences. Link the Shortcut story. -->

## AC
<!-- Concrete, checkable criteria or steps. Include the important behavior reviewers should verify. -->

## Deployment
<!-- Migrations, env vars, config, rollout order, manual steps. If none, say none. Include explicit not-a-problem context from task.md. -->

## Review notes
<!-- Optional but preferred for Codex: intentional trade-offs, naming that may look odd, scope reconciliation, privacy/data constraints, things not to flag. -->

## Manual QA
<!-- Optional. Include only if task.md records manual QA or concrete QA steps. -->
```
````

Mandatory sections must always be present:

- `## Summary`
- `## AC`
- `## Deployment`

Extra sections are allowed and encouraged when useful to AI review, especially:

- `## Review notes`
- `## Manual QA`

## Writing rules

- Plain English.
- Short, concrete bullets.
- Keep Codex as the reader: explain intent, accepted risks, and false-positive traps.
- Do not include AI attribution.
- Do not include raw PII, prospect emails, API keys, or raw provider responses.
- Link the Shortcut story as `Shortcut: sc-<task_id>` when `<task_id>` is numeric. If the task has a `Name`/story id that differs, use the id from the folder prefix.

## Content rules

### Summary

Write 2–4 sentences. Include:

- what changed;
- why it changed;
- the Shortcut reference.

### AC

Use bullets. Include checkable behavior, not vague goals.

When the task includes import/export workflows, include:

- mapping keys;
- idempotency rules;
- skip/reject rules;
- overwrite protections;
- send-gate or downstream state changes;
- output/privacy constraints.

### Deployment

State concrete deployment facts. If no migration/env change is needed, say so.

If `task.md` says DB recreation is safe because production is empty, include that so reviewers do not flag local DB recreation or migration churn incorrectly.

### Review notes

Use this for context Codex may miss, such as:

- intentional naming that may look backwards;
- documented scope reconciliation;
- observed vendor UI details that are not primary-source API docs;
- accepted trade-offs such as LinkedIn-only dedupe vs unsafe name matching;
- what should not be flagged.

### Manual QA

Include only if grounded in task text. If included, describe the flow and observed result without raw PII.
