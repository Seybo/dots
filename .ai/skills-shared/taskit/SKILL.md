---
name: taskit
description: >-
  Create a new local task folder and task.md file under /Volumes/dev/_tasks,
  or create a Shortcut story only when given a story ID or a task.md with complete Story details.
  Supports a manual task name, a Shortcut story ID, a task.md path, a draftNN reference,
  or inferring the project and Shortcut story ID from the current git branch.
  Command-only skill. In Pi, invoke via /skill:taskit; /taskit is also
  accepted where that alias is exposed.
disable-model-invocation: true
---

# Taskit

This is a command-only skill.

## Invocation

In Pi, use either:

```text
/skill:taskit
/taskit
/taskit <project>
/taskit <project> <task name>
/taskit <project> <story_id>
/taskit <project> <story_id> --base <full-base-branch-or-ref>
/taskit <project> <path-to-task.md>
/taskit <project> draftNN
```

With no arguments, infer both the project and Shortcut story ID from the current git checkout and branch.
With one token, treat it as `<project>` only when it matches an existing task project; otherwise infer `<project>` from the current working directory and treat the token as the selector/task name.
With two or more tokens, treat the first token as `<project>` only when it matches an existing task project; otherwise infer `<project>` from the current working directory and treat all tokens as the selector/task name.
`--base <full-base-branch-or-ref>` is optional for registered workspace Shortcut mode. It tells `/taskit` to create the generated task branch from that exact base branch/ref. Do not infer a base from a numeric parent task/story ID.

The selector/task name is interpreted as either:

- a **Shortcut story ID** if it is a single token of digits only (e.g. `12345`)
- a **draft reference** if it is a single token matching `^draft\d{2}$`, resolved to `/Volumes/dev/_tasks/<project>/draftNN/task.md`; Shortcut is used only if the file has complete `# Story details`
- a **task markdown path** if it is a single existing path ending in `.md` or `.markdown`; Shortcut is used only if the file has complete `# Story details`
- a **manual task name** otherwise (preserve spaces)

Examples:

```text
/taskit
/taskit shaka_gtm
/taskit my_budget_app Create budget tracking app
/taskit misc_notes Set up notes sync
/taskit shaka_gtm 147831
/taskit shaka_gtm 22222 --base origin/mikhail/sc-11111/parent-task
/taskit shaka_gtm /Volumes/dev/_tasks/shaka_gtm/123-foo/task.md
/taskit shaka_gtm draft01
/taskit my_budget_app draft01   # local conversion if task.md has no complete Story details
/taskit draft01                 # project inferred from cwd when possible
/taskit Switch to tmuxinator    # project inferred from cwd when possible
```

Do not auto-use this skill from a general task-management request. Wait for the explicit slash command.

## What it does

In manual mode, create a local task folder inside the selected project and create a `task.md` file inside it.

Shortcut is used only in explicit Shortcut mode: a numeric story ID, an inferred branch story ID, or an existing `task.md` whose first `# Story details` section has both `Name:` and `Epic:`.

For `draftNN` and task markdown path mode, inspect the existing file. If it has complete `# Story details`, create a Shortcut story and rename the folder to `<story_id>-<slug>`. Otherwise, treat it as a local-only draft/task and rename the folder to a sequential local task folder such as `0004-<slug>`.

## Project and branch resolution

Resolve `<project>`, the Shortcut story ID, the code working directory, and the
workspace using the shared rules in
[`~/.ai/skills-shared/components/task-resolution.md`](../components/task-resolution.md).
Read that file whenever any of these must be inferred. In short:

- `<project>` must match a first-level folder under `/Volumes/dev/_tasks/`.
- When the first token is not an existing task project, infer `<project>` from the current working directory and treat the whole input as the selector/task name.
- Infer the Shortcut story ID from the current branch's `sc-<digits>` segment.
- Preserve an optional `--base <full-base-branch-or-ref>` exactly for registered workspace branch creation; do not interpret it as part of the selector/task name.
- An inferred story ID is handled exactly like Shortcut mode.
- If a needed project cannot be inferred, ask the user to pass it explicitly. A story ID is needed only for no-argument or one-project Shortcut inference.

`taskit` only creates task folders under `/Volumes/dev/_tasks/<project>/`; it never
creates project roots or code checkouts.

## Instructions

1. **Parse command arguments:**
   - detect and remove an optional `--base <full-base-branch-or-ref>` pair before resolving `<project>` / selector; call the value `base_ref` when present; reject `--base` without a following value
   - if there are no tokens after `/taskit`, infer `<project>` and `<story_id>` from the current checkout and branch; if successful, use Shortcut mode
   - if there is exactly one token after `/taskit`:
     - if the token matches an existing task project, treat it as `<project>` and infer `<story_id>` from the current branch; if successful, use Shortcut mode; if no story ID can be inferred, ask the user for a task name, story ID, `draftNN`, or task markdown path
     - otherwise infer `<project>` from the current working directory and use the token as the selector/task name
   - if there are two or more tokens after `/taskit`:
     - if the first token matches an existing task project, extract it as `<project>` and use all remaining text as the selector/task name
     - otherwise infer `<project>` from the current working directory and use the full argument string as the selector/task name
   - decide the mode for the selector/task name in this order:
     - **Shortcut mode** if it is a single token matching `^\d+$`
     - **Draft reference mode** if it is a single token matching `^draft\d{2}$`; resolve it to `/Volumes/dev/_tasks/<project>/draftNN/task.md`, then handle it exactly like Task markdown path mode
     - **Task markdown path mode** if it is a single existing path ending in `.md` or `.markdown`
     - **Manual mode** otherwise
   - if the project or required selector is missing, ask the user to use:
     ```text
     /taskit
     /taskit <project>
     /taskit <project> <task name>
     /taskit <project> <story_id>
     /taskit <project> <story_id> --base <full-base-branch-or-ref>
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
   - **Task markdown path mode:** read the existing task file. If the first section named exactly `# Story details` has both `Name:` and `Epic:`, use Shortcut conversion and use the parsed `Name` as the task name. Otherwise use Local task-file conversion and derive the task name from the first meaningful heading or first non-empty content line; if no useful name can be derived, ask the user for a task name.
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
   - **Manual mode:** `{local_id}-{slug}` where `local_id` is the next zero-padded 4-digit local task ID for this project
     - choose `local_id` by scanning first-level folders under `/Volumes/dev/_tasks/<project>/` matching `^\d{4}-`, then using one greater than the highest existing local ID; if none exist, start at `0001`
     - ignore `draftNN` folders and Shortcut story ID folders when assigning local IDs
     - example: `0004-create-budget-tracking-app`
   - **Shortcut mode:** `{story_id}-{slug}`
     - example: `147831-toast-prepare-by-time-kitchen-ticket-time`
   - **Task markdown path mode with complete Story details:** after creating the Shortcut story, use `{created_story_id}-{slug}` using the created story's returned `id` and `name`
     - example: `147831-toast-prepare-by-time-kitchen-ticket-time`
   - **Task markdown path mode without complete Story details:** use Manual-mode local sequential naming `{local_id}-{slug}`

5. **Create or update the folder and file:**
   - **Manual and Shortcut modes:** create directory:
     ```text
     /Volumes/dev/_tasks/<project>/<folder-name>
     ```
   - **Manual and Shortcut modes:** create file:
     ```text
     /Volumes/dev/_tasks/<project>/<folder-name>/task.md
     ```
   - **Task markdown path mode:** do not create a new task file. Rename the existing task folder to the resolved folder name:
     ```text
     /Volumes/dev/_tasks/<project>/<story_id-or-local-id>-<slug>
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
   - in Task markdown path mode, show the old and new task folder paths; if Shortcut conversion happened, also show the created Shortcut story ID and URL

8. **Set up the development branch (registered workspace project, Shortcut mode only):**
   - This step runs for registered ordinal-workspace projects when the mode is Shortcut. Skip for Manual mode.
   - Each registered project has a code root with ordinal workspaces under it:
     ```text
     <code-root>/1st/
     <code-root>/7th/
     <code-root>/28th/
     ```
   - Choose the workspace using the "Selecting a workspace" rules in
     [`~/.ai/skills-shared/components/task-resolution.md`](../components/task-resolution.md).
   - Generate the branch name manually from the Shortcut story name:
     ```text
     mikhail/sc-{story_id}/{shortcut_story_name_slug}
     ```
     - Always use `mikhail` as the branch prefix, regardless of story owner.
     - Build `shortcut_story_name_slug` by slugifying the current Shortcut story `name` with the slug rules from step 3.
     - If the story was just fetched or created in this command, use that returned story `name`.
     - If the command is setting up a branch for an existing task folder, fetch the story first with the shared Shortcut CLI and use the returned `name`:
       ```bash
       ruby ~/.pi/agent/extensions/shortcut/scripts/shortcut.rb get-story <story_id>
       ```
     - Do not use the task folder suffix, `# Story details` local name, draft name, or any other local task title for the branch slug. Local task folders can drift from Shortcut titles; the branch slug must match Shortcut's Git Helper name.
     - Do NOT call `mcp__shortcut__stories-get-branch-name` — the MCP returns incorrect names (triple dashes, truncation).
   - Check the current branch in the selected workspace with `git -C <code-root>/<workspace> branch --show-current`.
     - If the current branch contains `sc-{story_id}` as a path segment, treat branch setup as already done and do not create or switch branches.
     - If the current branch differs from the generated branch name, report both the current branch and generated branch name.
   - If `base_ref` is present:
     - require a clean worktree before any checkout/branch creation:
       ```bash
       git -C <code-root>/<workspace> status --short
       ```
       If dirty, stop and ask the user to clean/commit/stash manually; do not stash automatically.
     - fetch remote refs so remote base branches are available:
       ```bash
       git -C <code-root>/<workspace> fetch origin
       ```
     - verify the exact base ref resolves to a commit:
       ```bash
       git -C <code-root>/<workspace> rev-parse --verify --quiet <base_ref>^{commit}
       ```
       If it does not resolve, stop and ask for a valid full branch/ref.
   - Verify whether the generated branch already exists in the selected checkout:
     ```bash
     git -C <code-root>/<workspace> rev-parse --verify --quiet <branch-name>
     ```
   - If the generated branch exists (exit 0):
     - If the current branch is not the generated branch, stop and ask the user how to proceed; do not switch silently.
     - If the current branch is the generated branch and `base_ref` is present, verify the base ref is contained in the task branch:
       ```bash
       git -C <code-root>/<workspace> merge-base --is-ancestor <base_ref> HEAD
       ```
       If that fails, stop and ask for explicit rebase or base-change instructions; do not rebase automatically.
   - If the generated branch does not exist (exit 1), create and check it out with exactly one of these forms — `-C` flag required, no `cd`, no bare `git`:
     ```bash
     git -C <code-root>/<workspace> checkout --no-track -b <branch-name> <base_ref>
     git -C <code-root>/<workspace> checkout -b <branch-name>
     ```
     Use the first form when `base_ref` is present; use the second form only when `base_ref` is absent. `--no-track` is required for explicit bases because when `<base_ref>` is a remote branch, Git may otherwise set the new task branch's upstream to the parent branch. The parent/base must stay in task/autowork config, not Git upstream.
   - Report the selected checkout, branch name, and base ref (when present) alongside the created paths from step 7.

## Task markdown path mode

This mode converts an existing task file into either a local task folder or a Shortcut story, depending only on the file contents.

### Shortcut conversion format

Shortcut conversion runs only when the file includes a first-level section named exactly:

```md
# Story details
```

Inside that section, before the next first-level heading, it must have these key/value lines:

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

If this section is absent or missing either `Name:` or `Epic:`, do not call Shortcut. Use Local task-file conversion instead.

### Description extraction for Shortcut conversion

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

Only for Shortcut conversion, use the shared Shortcut Ruby CLI, not MCP, to create the story:

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

### Local task-file conversion

When `# Story details` is absent or incomplete, do not call Shortcut. Convert the existing folder into a local task folder:

- derive the task name from the first meaningful heading or first non-empty content line in `task.md`
- if the only useful text is `# Context` or the file is otherwise empty, ask the user for a task name
- rename the existing task folder to local sequential naming:

```text
<NNNN>-<slugified-derived-task-name>
```

Do not modify `task.md` contents during local conversion unless the user explicitly asks.

### Rename task folder

For Shortcut conversion, after the story is created, rename the existing task folder to use Shortcut-origin naming:

```text
<created_story_id>-<slugified_created_story_name>
```

For Local task-file conversion, rename the existing task folder to use local sequential naming:

```text
<NNNN>-<slugified-derived-task-name>
```

Safety rules before renaming:

- draft references must resolve to an existing `/Volumes/dev/_tasks/<project>/draftNN/task.md`
- the provided markdown path must exist
- the file must be named `task.md`
- the file must be inside `/Volumes/dev/_tasks/<project>/`
- the parent task folder must be directly under `/Volumes/dev/_tasks/<project>/`
- the target folder must not already exist
- do not overwrite anything
- use a no-clobber rename shape for local draft conversion, e.g. `test ! -e /Volumes/dev/_tasks/<project>/<target> && mv -n /Volumes/dev/_tasks/<project>/draftNN /Volumes/dev/_tasks/<project>/<target>`

After successful rename, the task file path becomes:

```text
/Volumes/dev/_tasks/<project>/<story_id-or-local-id>-<slug>/task.md
```

Do not update `task.md` contents in this mode unless the user explicitly asks for that in a later request.

## Important Notes

- Manual and Shortcut modes are create-only; do not modify existing task folders or files in those modes
- Task markdown path mode may rename the existing task folder after Shortcut or local conversion, but must not otherwise modify `task.md` contents unless explicitly requested
- Preserve the original task name text only for slugification input; folder name uses the slugified form
- Local task IDs use zero-padded 4-digit IDs (`0001`, `0002`, ...). To choose the next local ID, scan first-level task folders under `/Volumes/dev/_tasks/<project>/` matching `^\d{4}-`, then use one greater than the highest existing local ID; if none exist, start at `0001`. Ignore `draftNN` folders and Shortcut story ID folders when assigning local IDs.
- If the generated folder already exists, stop and ask the user how to proceed rather than overwriting anything
- Do not create project folders automatically; only create task folders inside an existing project folder
- Do not add extra files
- Do not add extra sections to `task.md`
- For implementation-oriented tasks, later planning should use TDD where it makes sense, with specs focused on edge cases, boundaries, regressions, and acceptance criteria rather than only happy paths
- Do not auto-use this skill without the explicit `/taskit` command
- Step 8 branch setup applies to registered ordinal-workspace projects in Shortcut mode. Manual tasks do not touch git automatically.
