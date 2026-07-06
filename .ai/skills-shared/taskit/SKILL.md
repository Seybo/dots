---
name: taskit
description: >-
  Create a new task folder and task.md file for a project under /Volumes/dev/_tasks,
  or create a Shortcut story from an existing task.md file.
  Supports a manual task name, a Shortcut story ID, a task.md path, a draftNN reference,
  or inferring the project and Shortcut story ID from the current git branch.
  Command-only skill. Invoke only via /taskit.
---

# Taskit

This is a command-only skill.

## Invocation

Use only:

```text
/taskit
/taskit <project>
/taskit <project> <task name>
/taskit <project> <story_id>
/taskit <project> <path-to-task.md>
/taskit <project> draftNN
```

With no arguments, infer both the project and Shortcut story ID from the current git checkout and branch.
With only `<project>`, infer the Shortcut story ID from the current git branch.
With `<project>` plus more text, treat the first token after `/taskit` as the project name and treat the rest as either:

- a **Shortcut story ID** if it is a single token of digits only (e.g. `12345`)
- a **draft reference** if it is a single token matching `^draft\d{2}$`, resolved to `/Volumes/dev/_tasks/<project>/draftNN/task.md`
- a **task markdown path** if it is a single existing path ending in `.md` or `.markdown`
- a **manual task name** otherwise (preserve spaces)

Examples:

```text
/taskit
/taskit gtm
/taskit foo Create budget tracking app
/taskit bar Set up analytics events
/taskit ppm 147831
/taskit gtm /Volumes/dev/_tasks/gtm/123-foo/task.md
/taskit gtm draft01
```

Do not auto-use this skill from a general task-management request. Wait for the explicit slash command.

## What it does

In manual or Shortcut mode, create a task folder inside the selected project and create a `task.md` file inside it. Folder naming and `task.md` body depend on the input mode.

In task markdown path mode, including draft references, create a Shortcut story from an existing `task.md`, then rename the existing task folder to match the created Shortcut story using the same folder naming logic as Shortcut-origin tasks.

## Project and branch resolution

Resolve `<project>`, the Shortcut story ID, the code working directory, and the
GTM checkout using the shared rules in
[`~/.ai/skills-shared/components/task-resolution.md`](../components/task-resolution.md).
Read that file whenever any of these must be inferred. In short:

- `<project>` must match a first-level folder under `/Volumes/dev/_tasks/`.
- When `<project>` is not given, infer it from the current working directory.
- Infer the Shortcut story ID from the current branch's `sc-<digits>` segment.
- An inferred story ID is handled exactly like Shortcut mode.
- If a needed project or story ID cannot be inferred, ask the user to pass it explicitly.

`taskit` only creates task folders under `/Volumes/dev/_tasks/<project>/`; it never
creates project roots or code checkouts.

## Instructions

1. **Parse command arguments:**
   - if there are no tokens after `/taskit`, infer `<project>` and `<story_id>` from the current checkout and branch; if successful, use Shortcut mode
   - if there is exactly one token after `/taskit`, treat it as `<project>` and infer `<story_id>` from the current branch; if successful, use Shortcut mode
   - if there are two or more tokens after `/taskit`:
     - extract `<project>` as the first token after `/taskit`
     - take all remaining text after the project name and trim leading/trailing whitespace
     - decide the mode in this order:
       - **Shortcut mode** if the remainder is a single token matching `^\d+$`
       - **Draft reference mode** if the remainder is a single token matching `^draft\d{2}$`; resolve it to `/Volumes/dev/_tasks/<project>/draftNN/task.md`, then handle it exactly like Task markdown path mode
       - **Task markdown path mode** if the remainder is a single existing path ending in `.md` or `.markdown`
       - **Manual mode** otherwise
   - if the project or required inferred story ID is missing, ask the user to use:
     ```text
     /taskit
     /taskit <project>
     /taskit <project> <task name>
     /taskit <project> <story_id>
     /taskit <project> <path-to-task.md>
     /taskit <project> draftNN
     ```

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
   - **Draft reference mode:** resolve `draftNN` to `/Volumes/dev/_tasks/<project>/draftNN/task.md`, then follow Task markdown path mode.
   - **Task markdown path mode:** read the existing task file and parse the first section named exactly `# Story details`; see [Task markdown path mode](#task-markdown-path-mode). Use the parsed `Name` as the task name.
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
   - **Task markdown path mode:** after creating the Shortcut story, use `{created_story_id}-{slug}` using the created story's returned `id` and `name`
     - example: `147831-toast-prepare-by-time-kitchen-ticket-time`

5. **Create or update the folder and file:**
   - **Manual and Shortcut modes:** create directory:
     ```text
     /Volumes/dev/_tasks/<project>/<folder-name>
     ```
   - **Manual and Shortcut modes:** create file:
     ```text
     /Volumes/dev/_tasks/<project>/<folder-name>/task.md
     ```
   - **Task markdown path mode:** do not create a new task file. After creating the Shortcut story, rename the existing task folder to:
     ```text
     /Volumes/dev/_tasks/<project>/<created_story_id>-<slug>
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

7. **Return the created or updated path clearly:**
   - show the full task folder path
   - show the full `task.md` path
   - in Task markdown path mode, also show the created Shortcut story ID and URL, plus the old and new task folder paths

8. **Set up the development branch (GTM project, Shortcut mode only):**
   - This step runs only when `<project>` is `gtm` AND the mode is Shortcut. Skip for other projects or Manual mode.
   - GTM has multiple full-clone checkouts under:
     ```text
     /Volumes/dev/shaka/gtm/1st/
     /Volumes/dev/shaka/gtm/2nd/
     /Volumes/dev/shaka/gtm/3rd/
     ```
   - Choose the checkout using the "Selecting the GTM checkout" rules in
     [`~/.ai/skills-shared/components/task-resolution.md`](../components/task-resolution.md).
   - Generate the branch name manually:
     ```text
     mikhail/sc-{story_id}/{slug}
     ```
     - Always use `mikhail` as the branch prefix, regardless of story owner.
     - Do NOT call `mcp__shortcut__stories-get-branch-name` — the MCP returns incorrect names (triple dashes, truncation).
   - Check the current branch in the selected checkout with `git -C /Volumes/dev/shaka/gtm/<checkout> branch --show-current`.
     - If the current branch contains `sc-{story_id}` as a path segment, treat branch setup as already done and do not create or switch branches.
     - If the current branch differs from the generated branch name, report both the current branch and generated branch name.
   - Otherwise, verify the generated branch does not already exist in the selected checkout:
     ```bash
     git -C /Volumes/dev/shaka/gtm/<checkout> rev-parse --verify --quiet <branch-name>
     ```
   - If it exists (exit 0), stop and ask the user how to proceed.
   - Otherwise (exit 1), create and check out the branch with exactly this form — `-C` flag required, no `cd`, no bare `git`:
     ```bash
     git -C /Volumes/dev/shaka/gtm/<checkout> checkout -b <branch-name>
     ```
   - Report the selected checkout and branch name alongside the created paths from step 7.

## Task markdown path mode

This mode creates a Shortcut story from an existing task file.

### Required `task.md` format

The file must include a first-level section named exactly:

```md
# Story details
```

Inside that section, before the next first-level heading, require these key/value lines:

```md
Name: My Shortcut story title
Epic: 123
```

`Epic` may be either a numeric epic ID or a Shortcut epic URL containing `/epic/<id>/`.

Example:

```md
# Story details

Name: Create lead enrichment polling
Epic: https://app.shortcut.com/workspace/epic/123/epic-name

# Context

Build polling for enriched Clay data.

# Acceptance Criteria

- Data is retrieved safely
- Errors are surfaced clearly
```

### Description extraction

Do not send the `# Story details` section to Shortcut.

Send all remaining markdown after removing the entire `# Story details` section as the Shortcut story description. Preserve the remaining markdown exactly as much as practical, including headings and spacing.

For the example above, send:

```md
# Context

Build polling for enriched Clay data.

# Acceptance Criteria

- Data is retrieved safely
- Errors are surfaced clearly
```

### Create Shortcut story

Use the shared Shortcut Ruby CLI, not MCP, to create the story:

```bash
ruby ~/.pi/agent/extensions/shortcut/scripts/shortcut.rb create-story '<json>'
```

Important: pass the JSON payload string directly as the CLI argument. Do **not** pass a path to a JSON file; the CLI will treat the path text itself as JSON and fail.

The JSON must contain only:

```json
{
  "name": "<Name from Story details>",
  "epic_id": 123,
  "description": "<markdown after Story details>"
}
```

The Shortcut CLI adds the default team/workflow/state.

### Rename task folder

After the story is created, rename the existing task folder to use Shortcut-origin naming:

```text
<created_story_id>-<slugified_created_story_name>
```

Safety rules before renaming:

- draft references must resolve to an existing `/Volumes/dev/_tasks/<project>/draftNN/task.md`
- the provided markdown path must exist
- the file must be named `task.md`
- the file must be inside `/Volumes/dev/_tasks/<project>/`
- the parent task folder must be directly under `/Volumes/dev/_tasks/<project>/`
- the target folder must not already exist
- do not overwrite anything

After successful rename, the task file path becomes:

```text
/Volumes/dev/_tasks/<project>/<created_story_id>-<slug>/task.md
```

Do not update `task.md` contents in this mode unless the user explicitly asks for that in a later request.

## Important Notes

- Manual and Shortcut modes are create-only; do not modify existing task folders or files in those modes
- Task markdown path mode may rename the existing task folder after creating the Shortcut story, but must not otherwise modify `task.md` contents unless explicitly requested
- Preserve the original task name text only for slugification input; folder name uses the slugified form
- Use the local timezone of the current machine for the timestamp (manual mode only)
- If the generated folder already exists, stop and ask the user how to proceed rather than overwriting anything
- Do not create project folders automatically; only create task folders inside an existing project folder
- Do not add extra files
- Do not add extra sections to `task.md`
- For implementation-oriented tasks, later planning should use TDD where it makes sense, with specs focused on edge cases, boundaries, regressions, and acceptance criteria rather than only happy paths
- Do not auto-use this skill without the explicit `/taskit` command
- Step 8 (branch setup) is GTM-specific and Shortcut-mode-only. For Manual mode in GTM, or any non-GTM project, do not touch git.
