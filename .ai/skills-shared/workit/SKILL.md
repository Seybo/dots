---
name: workit
description: >-
  Start work on an existing task folder under /Volumes/dev/_tasks.
  Reads the task's task.md and proceeds with the work it describes.
  Command-only skill. Invoke only via /workit.
---

# Workit

This is a command-only skill.

## Invocation

Use only:

```text
/workit <project> <task_id>
```

Treat the first token after `/workit` as the project name.
Treat the second token as the task identifier — must be **digits only**, matching either:

- a **Shortcut story ID** (e.g. `147831`)
- a **timestamp** prefix from a manually-created folder (e.g. `202605051437`)

The identifier is matched as a prefix of the task folder name. Passing `147831` finds a folder like `147831-toast-prepare-by-time`. Passing `202605051437` finds `202605051437-create-budget-tracking-app`.

Examples:

```text
/workit foo 147831
/workit bar 202605051437
```

Do not auto-use this skill from a general "work on this task" request. Wait for the explicit slash command.

## What it does

Locate an existing task folder under the selected project, read its `task.md`, and proceed with the work described in it.

Companion to `/taskit` (which creates the folder). `/workit` consumes folders that `/taskit` produced.

## Project resolution

Projects live under:

- `/Volumes/dev/_tasks/`

The project name passed to the command must match a first-level folder name under `/Volumes/dev/_tasks/`.

## Instructions

1. **Parse command arguments:**
   - extract `<project>` as the first token after `/workit`
   - extract `<task_id>` as the second token
   - validate that `<task_id>` matches `^\d+$` (digits only); otherwise ask the user to pass a story ID or a timestamp
   - if either argument is missing, ask the user to use:
     ```text
     /workit <project> <task_id>
     ```

2. **Resolve and validate project:**
   - resolve the project root as:
     ```text
     /Volumes/dev/_tasks/<project>/
     ```
   - if that folder does not exist, tell the user the project was not found
   - do not create project folders automatically

3. **Locate the task folder:**
   - glob `<project_root>/<task_id>*` to find matching task folders (prefix match)
   - exactly one match expected:
     - **zero matches:** stop and report that no task folder starts with `<task_id>` under the project
     - **multiple matches:** stop and ask the user to disambiguate, listing the matches
   - confirm the matched folder contains `task.md`; if not, stop and report the missing file

4. **Load the task:**
   - read `<task_folder>/task.md` once at the start
   - any project-level `CLAUDE.md` in the project root or current working directory will be picked up automatically by the agent — do not re-read it as a separate step unless asked
   - do not modify `task.md` unless the user asks you to

5. **Proceed with the task:**
   - work on what `task.md` describes
   - if the body is just `# Context` with no further instructions, ask the user what they want done before proceeding

6. **After completing the task:**
   - re-read `task.md` and verify nothing was missed
   - report what was done

## Important Notes

- Do not auto-use this skill without the explicit `/workit` command
- Do not create or modify task folders here — that is `/taskit`'s job
- Do not modify `task.md` content unless explicitly asked
- The task folder must already exist; if it doesn't, suggest the user run `/taskit` first
