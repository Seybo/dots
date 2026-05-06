---
name: taskit
description: >-
  Create a new task folder and task.md file for a project under /Volumes/dev/_tasks.
  Supports a manual task name or a Shortcut story ID.
  Command-only skill. Invoke only via /taskit.
---

# Taskit

This is a command-only skill.

## Invocation

Use only:

```text
/taskit <project> <task name>
/taskit <project> <story_id>
```

Treat the first token after `/taskit` as the project name.
Treat the rest as either:

- a **Shortcut story ID** if it is a single token of digits only (e.g. `12345`)
- a **manual task name** otherwise (preserve spaces)

Examples:

```text
/taskit foo Create budget tracking app
/taskit bar Set up analytics events
/taskit ppm 147831
```

Do not auto-use this skill from a general task-management request. Wait for the explicit slash command.

## What it does

Create a task folder inside the selected project and create a `task.md` file inside it. Folder naming and `task.md` body depend on the input mode (manual vs Shortcut).

## Project resolution

Projects live under:

- `/Volumes/dev/_tasks/`

The project name passed to the command must match a first-level folder name under `/Volumes/dev/_tasks/`.

Examples:

- project `foo` → `/Volumes/dev/_tasks/foo/`
- project `bar` → `/Volumes/dev/_tasks/bar/`

## Instructions

1. **Parse command arguments:**
   - extract `<project>` as the first token after `/taskit`
   - take all remaining text after the project name and trim leading/trailing whitespace
   - if the project or the remainder is missing, ask the user to use:
     ```text
     /taskit <project> <task name>
     /taskit <project> <story_id>
     ```
   - decide the mode:
     - **Shortcut mode** if the remainder is a single token matching `^\d+$`
     - **Manual mode** otherwise

2. **Resolve and validate project:**
   - resolve the project root as:
     ```text
     /Volumes/dev/_tasks/<project>/
     ```
   - if that folder does not exist, tell the user the project was not found
   - do not create project folders automatically

3. **Resolve task name and slug:**
   - **Manual mode:** use the remainder as the task name
   - **Shortcut mode:** call `mcp__shortcut__stories-get-by-id` with the story ID; use the story's `name` as the task name and the story's `description` as the body. If the call fails or the story is missing, stop and report the error.
   - slugify the task name:
     - lowercase everything
     - replace spaces with `-`
     - remove characters except letters, numbers, and `-`
     - collapse repeated separators into a single `-`
     - trim leading and trailing `-`
     - example:
       - `Create budget tracking app` → `create-budget-tracking-app`
       - `Create budget: tracking app!` → `create-budget-tracking-app`

4. **Build the task folder name:**
   - **Manual mode:** `{timestamp}-{slug}` where timestamp is local-machine time formatted as `YYYYMMDDHHMM` (e.g. `date +%Y%m%d%H%M`)
     - example: `202605051437-create-budget-tracking-app`
   - **Shortcut mode:** `{story_id}-{slug}`
     - example: `147831-toast-prepare-by-time-kitchen-ticket-time`

5. **Create the folder and file:**
   - create directory:
     ```text
     /Volumes/dev/_tasks/<project>/<folder-name>
     ```
   - create file:
     ```text
     /Volumes/dev/_tasks/<project>/<folder-name>/task.md
     ```

6. **Write the initial file contents:**
   - **Manual mode:**
     ```md
     # Context
     ```
   - **Shortcut mode:**
     ```md
     # Context

     {story_description}
     ```
     - If the story description is empty, write only `# Context` with no body.

7. **Return the created path clearly:**
   - show the full task folder path
   - show the full `task.md` path

## Important Notes

- Create only; do not modify existing task folders or files
- Preserve the original task name text only for slugification input; folder name uses the slugified form
- Use the local timezone of the current machine for the timestamp (manual mode only)
- If the generated folder already exists, stop and ask the user how to proceed rather than overwriting anything
- Do not create project folders automatically; only create task folders inside an existing project folder
- Do not add extra files
- Do not add extra sections to `task.md`
- Do not auto-use this skill without the explicit `/taskit` command
