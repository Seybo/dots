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
/workit <project> [task_id]
```

Treat the first token after `/workit` as the project name.
Treat the optional second token as the task identifier — must be **digits only**, matching either:

- a **Shortcut story ID** (e.g. `147831`)
- a **timestamp** prefix from a manually-created folder (e.g. `202605051437`)

The identifier is matched as a prefix of the task folder name. Passing `147831` finds a folder like `147831-toast-prepare-by-time`. Passing `202605051437` finds `202605051437-create-budget-tracking-app`.

Examples:

```text
/workit foo
/workit foo 147831
/workit bar 202605051437
```

Do not auto-use this skill from a general "work on this task" request. Wait for the explicit slash command.

## What it does

Locate an existing task folder under the selected project, read its `task.md`, and proceed with the work described in it.

Companion to `/taskit` (which creates the folder). `/workit` consumes folders that `/taskit` produced.

## Project resolution

The `<project>` argument resolves to two locations:

- **Task folder root:** `/Volumes/dev/_tasks/<project>/` — where the task definition (`task.md`) lives.
- **Code working directory:** `/Volumes/dev/shaka/<project>/` — the codebase to operate on when the task does not name its own working directory.

The project name must match a first-level folder name under `/Volumes/dev/_tasks/`. The matching folder under `/Volumes/dev/shaka/` is the default working directory for any work the task describes.

## Instructions

1. **Parse command arguments:**
   - extract `<project>` as the first token after `/workit`
   - extract optional `<task_id>` as the second token
   - if `<project>` is missing, ask the user to use:
     ```text
     /workit <project> [task_id]
     ```
   - if `<task_id>` is present, validate that it matches `^\d+$` (digits only); otherwise ask the user to pass a story ID or a timestamp
   - if `<task_id>` is missing, continue through project validation, then list recent tasks as described below

2. **Resolve and validate project:**
   - resolve the task root as:
     ```text
     /Volumes/dev/_tasks/<project>/
     ```
   - if that folder does not exist, tell the user the project was not found
   - do not create project folders automatically
   - also note the default code working directory:
     ```text
     /Volumes/dev/shaka/<project>/
     ```
     This is where the task's work should happen unless `task.md` names a different directory. Do not fail if it does not exist — just do not assume it.

3. **If no task identifier was provided, offer recent tasks:**
   - list the 10 most recently created task folders under `<project_root>`
     - prefer filesystem creation/birth time when available
     - if creation time is unavailable, fall back to modification time, then folder name ordering
   - include each task's selection number, folder name, and the first Markdown heading or first non-empty line from `task.md` when available
   - ask the user which task to work on
   - accept the user's reply as either:
     - a displayed selection number (`1`-`10`)
     - a digits-only task identifier / prefix
   - after the user replies, resolve the selected task and continue with the next step
   - if there are no task folders under the project, stop and say none were found; suggest `/taskit`

4. **Locate the task folder:**
   - glob `<project_root>/<task_id>*` to find matching task folders (prefix match), unless the user chose a displayed selection number from the recent-tasks list
   - exactly one match expected:
     - **zero matches:** stop and report that no task folder starts with `<task_id>` under the project
     - **multiple matches:** stop and ask the user to disambiguate, listing the matches
   - confirm the matched folder contains `task.md`; if not, stop and report the missing file

5. **Load the task:**
   - read `<task_folder>/task.md` once at the start
   - any project-level `CLAUDE.md` in the project root or current working directory will be picked up automatically by the agent — do not re-read it as a separate step unless asked
   - do not modify `task.md` unless the user asks you to

6. **Proceed with the task:**
   - work on what `task.md` describes
   - if `task.md` does not name a working directory, default to `/Volumes/dev/shaka/<project>/`
   - only `task.md` defines the work — do not read other files in the task folder (e.g. `next.md`, notes, drafts) as instructions unless `task.md` explicitly references them
   - if the body is just `# Context` (or otherwise empty of instructions), ask the user what they want done before proceeding

7. **After completing the task:**
   - re-read `task.md` and verify nothing was missed
   - report what was done

## Important Notes

- Do not auto-use this skill without the explicit `/workit` command
- Do not create or modify task folders here — that is `/taskit`'s job
- Do not modify `task.md` content unless explicitly asked
- The task folder must already exist; if it doesn't, suggest the user run `/taskit` first
