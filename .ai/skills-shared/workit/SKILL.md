---
name: workit
description: >-
  Start work on an existing task folder under /Volumes/dev/_tasks.
  Reads the task's task.md and proceeds with the work it describes.
  Can infer the project and task/story ID from the current git branch.
  Supports create-steps-only mode for /autowork preflight.
  Command-only skill. In Pi, invoke via /skill:workit; /workit is also
  accepted where that alias is exposed.
---

# Workit

This is a command-only skill.

## Invocation

In Pi, use either:

```text
/skill:workit
/workit
/workit <project-or-session> [task_id]
/workit <project-or-session> [task_id] --base <full-base-branch-or-ref>
/workit <project-or-session> [task_id] create-steps-only
/workit <project-or-session> [task_id] --base <full-base-branch-or-ref> create-steps-only
/workit <project-or-session> [task_id] step <step_number>
```

With no arguments, infer the project from the current git checkout; if a Shortcut story ID can also be inferred from the branch, use it, otherwise list recent tasks for the inferred project.
With one token, treat it as `<project-or-session>` only when it matches an existing task project or registered session alias; otherwise infer `<project>` from the current working directory and treat the token as the task identifier.
With `<project-or-session> <task_id>`, treat the first token after `/workit` as the project name or registered session alias and the second token as the task identifier — must be **digits only**, matching either:

- a **Shortcut story ID** (e.g. `147831`)
- a **local sequential task ID** (e.g. `0003`)

The identifier is matched as a prefix of the task folder name. Passing `147831` finds a folder like `147831-toast-prepare-by-time`. Passing `0003` finds `0003-bootstrap-ruby-sqlite-app`.

`--base <full-base-branch-or-ref>` is an optional stacked-branch setup argument. It tells `/workit` to create or verify the task branch from that exact base branch/ref. Do not infer a base from a numeric parent task/story ID.

`create-steps-only` mode adds a trailing `create-steps-only` clause. It resolves the task, performs the normal branch setup/verification, creates or updates `steps.md`, then stops without implementing any step.

Step mode adds a trailing `step <step_number>` clause. It executes exactly one existing `steps.md` step and then stops without committing. The step number must be digits only.

Examples:

```text
/workit
/workit shaka_gtm
/workit shaka_gtm1 147831
/workit shaka_gtm 147831
/workit my_health 0003
/workit 0003      # project inferred from cwd when possible
/workit shaka_gtm1 147831 create-steps-only
/workit shaka_gtm2 22222 --base origin/mikhail/sc-11111/parent-task create-steps-only
/workit 0003 create-steps-only
/workit shaka_gtm1 147831 step 2
/workit 0003 step 1
```

Do not auto-use this skill from a general "work on this task" request. Wait for the explicit slash command. Exception: `/autowork` may invoke `/workit ... create-steps-only` as its documented preflight subroutine after the user explicitly invokes `/autowork`.

## What it does

Locate an existing task folder under the selected project, read its `task.md`, create a `steps.md` implementation plan first, and then proceed with the work described in it.

In `create-steps-only` mode, create or update `steps.md` using the normal planning rules, then stop. Do not implement any step, do not edit production code, do not stage, and do not commit. This mode exists so `/autowork` can ensure a task has a plan before the autonomous commit/review loop starts.

In `step <step_number>` mode, `steps.md` must already exist and must contain parseable headings like `## Step 1: ...`. Execute only the requested step and stop. Do not create/update the plan in step mode except to report that it is missing, stale, ambiguous, or impossible to follow.

Companion to `/taskit` (which creates the folder). `/workit` consumes folders that `/taskit` produced.

## Project and branch resolution

Resolve `<project>`, the task/story ID, the code working directory, and the workspace
using the shared rules in
[`~/.ai/skills-shared/components/task-resolution.md`](../components/task-resolution.md).
Read that file whenever any of these must be inferred or normalized. `<project>` resolves to two
locations: the task folder root `/Volumes/dev/_tasks/<project>/` (where `task.md`
lives) and the code working directory (see the shared registry's mapping). Registered session
aliases such as `shaka_gtm1`, `shaka_gtm7`, and `shaka_trp28` normalize to their task project
and select the matching ordinal workspace. Applied to `/workit`:

- With no arguments, infer `<project>` from the current working directory and infer the task/story ID from the current branch when possible; if the project is inferred but no task/story ID is found, keep the normal recent-task picker.
- With `/workit <project-or-session>`, infer only the task/story ID from the current branch
  when possible; if none can be inferred, keep the normal recent-task picker.
- With `/workit <task_id>`, when the token is not an existing task project or registered session alias, infer `<project>` from the current working directory and use the token as the task/story ID.
- With `--base <full-base-branch-or-ref>`, preserve the base ref exactly for branch setup/verification. Do not treat it as a task selector.
- An inferred story ID is used as the same prefix-matched task identifier as an
  explicit `<task_id>`.
- If `/workit` has no arguments and the project cannot be inferred, ask the user to pass it explicitly.

## Instructions

1. **Parse command arguments:**
   - detect and remove an optional `--base <full-base-branch-or-ref>` pair before resolving `<project>` / `<task_id>`; call the value `base_ref` when present; reject `--base` without a following value
   - detect and remove an optional trailing `create-steps-only` clause before resolving `<project>` / `<task_id>`; call this `create_steps_only_mode` when present
   - detect and remove an optional trailing `step <step_number>` clause before resolving `<project>` / `<task_id>`; validate `<step_number>` with `^[0-9]+$`; call this `step_mode` when present
   - reject commands that combine `create-steps-only` with `step <step_number>`; these modes are mutually exclusive
   - if there are no tokens after `/workit`, infer `<project>` from the current checkout and infer `<task_id>` from the current branch when possible; if no story ID can be inferred, leave `<task_id>` missing
   - if there is exactly one token after `/workit`:
     - if the token matches an existing task project or registered session alias, treat it as `<project>` or a registered session alias and try to infer `<task_id>` from the current branch; if no story ID can be inferred, leave `<task_id>` missing
     - otherwise infer `<project>` from the current working directory and use the token as `<task_id>`
   - if there are two tokens after `/workit`:
     - extract `<project>` or a registered session alias as the first token after `/workit`
     - extract `<task_id>` as the second token
   - if `<project>` is missing, ask the user to use:
     ```text
     /workit
     /workit <project-or-session> [task_id]
     ```
   - if `<task_id>` is present, validate that it matches `^\d+$` (digits only); otherwise ask the user to pass a Shortcut story ID or local sequential task ID such as `0003`
   - if `<task_id>` is missing, continue through project validation, then list recent tasks as described below
   - if `base_ref` is present, keep it as a full Git branch/ref string for branch setup; do not resolve it through task folders or Shortcut

2. **Resolve and validate project:**
   - normalize any registered session alias using the shared task-resolution rules; its trailing
     number selects the matching ordinal workspace (`shaka_trp28` → `28th`)
   - resolve the task root from the normalized project as:
     ```text
     /Volumes/dev/_tasks/<project>/
     ```
   - never look for a session alias under `/Volumes/dev/_tasks/`; session aliases are not task roots
   - if that folder does not exist, tell the user the project was not found
   - do not create project folders automatically
   - resolve the code working directory from the shared project registry; this is the only
     place where implementation work should happen:
     ```text
     <registered-code-root>/<ordinal-workspace>/
     ```
   - Choose the workspace using the "Selecting a workspace" rules in
     [`~/.ai/skills-shared/components/task-resolution.md`](../components/task-resolution.md).
     Do not fail if the resolved code working directory does not exist — just do not assume it.

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

6. **Verify/setup the development branch before implementation or create-steps-only planning:**
   - before making any production code, docs, bin, config, schema, or spec changes in the code working directory, and before returning from `create_steps_only_mode` for `/autowork`, check the current branch with:
     ```bash
     git -C <code-working-directory> branch --show-current
     ```
   - **Never work on `main` except for the `env` project (`/Users/inseybo/.dots`).** If the current branch is `main` and the resolved project is not `env`, stop before editing and switch to a task branch. For `env`, working on `main` is allowed.
   - **Never work on `master` for non-`my_*` projects.** If the current branch is `master` and the resolved project does not start with `my_`, stop before editing and switch to a task branch. For `my_*` projects, working on `master` is allowed.
   - For registered workspace Shortcut tasks, follow the branch setup rules from [`taskit` step 8: Set up the development branch](../taskit/SKILL.md#set-up-the-development-branch-gtm-project-shortcut-mode-only): fetch the Shortcut story, generate `mikhail/sc-{story_id}/{shortcut_story_name_slug}` from the returned story `name`, verify whether it already exists, and create it when safe. Do not use the task folder suffix as the branch slug; existing task folders can have local/draft slugs that differ from Shortcut's Git Helper slug.
   - If `base_ref` is present for a registered workspace Shortcut task:
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
     - if the generated task branch does not exist, create it from the exact base ref without configuring the base as Git upstream/tracking branch:
       ```bash
       git -C <code-root>/<workspace> checkout --no-track -b <branch-name> <base_ref>
       ```
       `--no-track` is required because when `<base_ref>` is a remote branch, Git may otherwise set the task branch's upstream to the parent branch. The parent/base must stay in `/autowork` config, not Git upstream.
       Report that `<branch-name>` was created from `<base_ref>`.
     - if the generated task branch already exists and the current branch is not that branch, stop and ask before switching. When running as `/autowork` preflight, stop and report the needed branch decision instead of switching.
     - if the generated task branch already exists and the current branch is that branch, verify the base ref is already contained in the task branch:
       ```bash
       git -C <code-root>/<workspace> merge-base --is-ancestor <base_ref> HEAD
       ```
       If this fails, the parent/base branch likely advanced or the branch was created from a different base. Stop and ask for explicit rebase or base-change instructions; do not rebase automatically.
   - If `base_ref` is not present and a task branch already exists, ask the user whether to switch to it unless the current branch already contains `sc-{task_id}` as a path segment. When running as `/autowork` preflight, stop and report the needed branch decision instead of continuing on the wrong branch.
   - If `base_ref` is not present and the generated task branch does not exist, create it from the current HEAD using the existing taskit branch rules.
   - If the task is manual or the correct branch name is unclear, ask the user for the branch name. Do not guess and do not continue on `master` or `main`, except that `main` is allowed for the `env` project (`/Users/inseybo/.dots`). When running as `/autowork` preflight, stop and report that a branch decision is required.

7. **Create or load the steps plan before implementation:**
   - before writing or updating `steps.md`, inspect existing implementation patterns relevant to the task:
     - for services, read nearby services with similar names, responsibilities, or folder structure
     - for CLIs/commands, read adjacent command parsers and bin wrappers
     - for APIs/integrations, read existing API clients, retry/error handling, request/response objects, and specs for the same or adjacent provider
     - for schemas/migrations, read nearby migrations, schema specs, timestamp/id conventions, and application code that writes those tables
     - for artifacts/state/docs, read existing artifact path helpers, state layout, operator-facing skill docs, and reporting templates
   - reflect the discovered patterns in `steps.md` with concrete behavior, not vague references such as "match existing behavior" or "be consistent"; write the actual rule to follow
   - if existing implementations disagree or contain flaws, mention the inconsistency in `steps.md` and propose whether the task should update all files sharing that pattern, defer a follow-up, or intentionally keep the local behavior different; do not silently choose a one-off pattern
   - before making production code/docs changes for the task, ensure `<task_folder>/steps.md` exists
   - in `create_steps_only_mode`, create or update `<task_folder>/steps.md` as needed, then stop immediately after reporting the path and branch status; do not ask to proceed with implementation
   - in `step_mode`, if `steps.md` is missing, stop and tell the user to run `/workit` without `step` first to create and approve the plan
   - if `steps.md` already exists, read it and follow it; update it only if the task needs a corrected or more incremental plan and `step_mode` is not active
   - if `steps.md` is missing and `step_mode` is not active, create it first from `task.md` before implementation
   - after creating `steps.md`, or after making substantive updates to an existing `steps.md`, stop and ask the user to review/confirm the plan before making production code/docs changes, except in `create_steps_only_mode`, where stopping after plan creation/update is the whole command and no implementation confirmation is needed
   - write `steps.md` using simple, precise technical language
   - structure `steps.md` as gradual, reviewable implementation slices; each step should leave the repo in a working state
   - use parseable step headings for every step:
     ```md
     ## Step 1: Short title
     ## Step 2: Short title
     ```
     The canonical step parser is `^## Step ([0-9]+)\b`.
   - when the task has testable behavior, use TDD where it makes sense: write or update failing specs for each implementation slice before changing production code, then implement until they pass
   - focus specs on edge cases, boundaries, regressions, and acceptance criteria rather than only happy paths
   - start with the smallest deterministic/local behavior and slowly add complexity, edge cases, persistence, integration, and docs
   - preserve existing logic/behavior as much as possible; do not add new features, new policy, theoretical fields, or imaginary scenario handling beyond the task scope
   - when adding schema, commands, config, APIs, artifacts, or persisted fields, include only what is grounded in `task.md`, current docs, or existing implementation behavior; do not add speculative/provenance/convenience fields unless the task explicitly asks for them or existing runtime behavior requires them
   - boolean fields must be named with an `is_` or `has_` prefix (prefer `is_` when natural), must be `NOT NULL`, and must have an explicit default value
   - fix real bugs discovered in existing logic when they block correctness or violate documented behavior
   - actively notice and capture useful improvements, validations, edge-case handling, and behavior changes; if they are not already in the task/current implementation, keep them out of the implementation and propose them to the user as a separate follow-up conversation before doing that work
   - keep the plan aligned with the task's acceptance criteria and non-goals

8. **Proceed with the task:**
   - work in the resolved code working directory
   - work on what `task.md` describes, following `steps.md` incrementally
   - in `create_steps_only_mode`, do not enter this implementation step; the command is complete after branch setup/verification and `steps.md` creation/update
   - in `step_mode`, locate the exact requested section from `## Step N` up to before the next `## Step <number>` heading; read full `steps.md` for context but implement only that section
   - in `step_mode`, treat `steps.md` as frozen; if the step is missing, ambiguous, stale, impossible, or requires a plan change, stop and report instead of silently editing the plan
   - in `step_mode`, do not commit; leave code changes unstaged/uncommitted for the orchestrator, and report changes/checks/open questions/deviations before stopping
   - after completing each numbered step/slice from `steps.md`, stop and report the changes made, checks run, open questions, and any deviations or findings; ask the user to confirm before starting the next step
   - do not continue into the next `steps.md` step without explicit user confirmation, even if the next step seems obvious or mechanical
   - if the user has questions, requests changes, or wants to adjust scope at a step boundary, handle that before proceeding
   - only `task.md` and `steps.md` define the work — do not read other files in the task folder (e.g. `next.md`, notes, drafts) as instructions unless `task.md` explicitly references them
   - if the body is just `# Context` (or otherwise empty of instructions), ask the user what they want done before proceeding

9. **After completing the task:**
   - re-read `task.md` and `steps.md` and verify nothing was missed
   - report what was done
   - separately propose all improvements, findings, validations, edge cases, follow-up tasks, and behavior changes you noticed but intentionally did not implement because they were outside the current task/current behavior

## Important Notes

- Do not auto-use this skill without the explicit `/workit` command, except for `/autowork` invoking `/workit ... create-steps-only` as its documented preflight
- Do not create or modify task folders here except for creating/updating the selected task's `steps.md` implementation plan
- Do not modify `task.md` content unless explicitly asked
- The task folder must already exist; if it doesn't, suggest the user run `/taskit` first
