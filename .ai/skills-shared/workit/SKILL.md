---
name: workit
description: >-
  Start work on an existing task folder under /Volumes/dev/_tasks.
  Reads the task's task.md and proceeds with the work it describes.
  Can infer the project and task/story ID from the current git branch.
  Command-only skill. Invoke only via /workit.
---

# Workit

This is a command-only skill.

## Invocation

Use only:

```text
/workit
/workit <project> [task_id]
```

With no arguments, infer both the project and Shortcut story ID from the current git checkout and branch.
With only `<project>`, infer the Shortcut story ID from the current branch when possible; otherwise list recent tasks as before.
With `<project> <task_id>`, treat the first token after `/workit` as the project name and the second token as the task identifier — must be **digits only**, matching either:

- a **Shortcut story ID** (e.g. `147831`)
- a **timestamp** prefix from a manually-created folder (e.g. `202605051437`)

The identifier is matched as a prefix of the task folder name. Passing `147831` finds a folder like `147831-toast-prepare-by-time`. Passing `202605051437` finds `202605051437-create-budget-tracking-app`.

Examples:

```text
/workit
/workit foo
/workit foo 147831
/workit bar 202605051437
```

Do not auto-use this skill from a general "work on this task" request. Wait for the explicit slash command.

## What it does

Locate an existing task folder under the selected project, read its `task.md`, create a `steps.md` implementation plan first, and then proceed with the work described in it.

Companion to `/taskit` (which creates the folder). `/workit` consumes folders that `/taskit` produced.

## Project and branch resolution

Resolve `<project>`, the task/story ID, the code working directory, and the GTM
checkout using the shared rules in
[`~/.ai/skills-shared/components/task-resolution.md`](../components/task-resolution.md).
Read that file whenever any of these must be inferred. `<project>` resolves to two
locations: the task folder root `/Volumes/dev/_tasks/<project>/` (where `task.md`
lives) and the code working directory (see the shared doc's mapping). Applied to
`/workit`:

- With no arguments, infer both `<project>` and the task/story ID from the current
  working directory and branch.
- With `/workit <project>`, infer only the task/story ID from the current branch
  when possible; if none can be inferred, keep the normal recent-task picker.
- An inferred story ID is used as the same prefix-matched task identifier as an
  explicit `<task_id>`.
- If `/workit` has no arguments and the project or story ID cannot be inferred,
  ask the user to pass it explicitly.

## Instructions

1. **Parse command arguments:**
   - if there are no tokens after `/workit`, infer `<project>` and `<task_id>` from the current checkout and branch
   - if there is exactly one token after `/workit`, treat it as `<project>` and try to infer `<task_id>` from the current branch; if no story ID can be inferred, leave `<task_id>` missing
   - if there are two tokens after `/workit`:
     - extract `<project>` as the first token after `/workit`
     - extract `<task_id>` as the second token
   - if `<project>` is missing, ask the user to use:
     ```text
     /workit
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
     /Volumes/dev/shaka/gtm/<checkout>/ # when <project> is gtm; checkout is 1st, 2nd, or 3rd
     /Volumes/dev/mydev/<project>/      # when <project> starts with my_
     /Volumes/dev/shaka/<project>/      # otherwise
     ```
   - For GTM, choose the checkout using the "Selecting the GTM checkout" rules in
     [`~/.ai/skills-shared/components/task-resolution.md`](../components/task-resolution.md).
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

6. **Create or load the steps plan before implementation:**
   - before writing or updating `steps.md`, inspect existing implementation patterns relevant to the task:
     - for services, read nearby services with similar names, responsibilities, or folder structure
     - for CLIs/commands, read adjacent command parsers and bin wrappers
     - for APIs/integrations, read existing API clients, retry/error handling, request/response objects, and specs for the same or adjacent provider
     - for schemas/migrations, read nearby migrations, schema specs, timestamp/id conventions, and application code that writes those tables
     - for artifacts/state/docs, read existing artifact path helpers, state layout, operator-facing skill docs, and reporting templates
   - reflect the discovered patterns in `steps.md` with concrete behavior, not vague references such as "match existing behavior" or "be consistent"; write the actual rule to follow
   - if existing implementations disagree or contain flaws, mention the inconsistency in `steps.md` and propose whether the task should update all files sharing that pattern, defer a follow-up, or intentionally keep the local behavior different; do not silently choose a one-off pattern
   - before making production code/docs changes for the task, ensure `<task_folder>/steps.md` exists
   - if `steps.md` already exists, read it and follow it; update it only if the task needs a corrected or more incremental plan
   - if `steps.md` is missing, create it first from `task.md` before implementation
   - after creating `steps.md`, or after making substantive updates to an existing `steps.md`, stop and ask the user to review/confirm the plan before making production code/docs changes
   - write `steps.md` using simple, precise technical language
   - structure `steps.md` as gradual, reviewable implementation slices; each step should leave the repo in a working state
   - when the task has testable behavior, use TDD where it makes sense: write or update failing specs for each implementation slice before changing production code, then implement until they pass
   - focus specs on edge cases, boundaries, regressions, and acceptance criteria rather than only happy paths
   - start with the smallest deterministic/local behavior and slowly add complexity, edge cases, persistence, integration, and docs
   - preserve existing logic/behavior as much as possible; do not add new features, new policy, theoretical fields, or imaginary scenario handling beyond the task scope
   - when adding schema, commands, config, APIs, artifacts, or persisted fields, include only what is grounded in `task.md`, current docs, or existing implementation behavior; do not add speculative/provenance/convenience fields unless the task explicitly asks for them or existing runtime behavior requires them
   - boolean fields must be named with an `is_` or `has_` prefix (prefer `is_` when natural), must be `NOT NULL`, and must have an explicit default value
   - fix real bugs discovered in existing logic when they block correctness or violate documented behavior
   - actively notice and capture useful improvements, validations, edge-case handling, and behavior changes; if they are not already in the task/current implementation, keep them out of the implementation and propose them to the user as a separate follow-up conversation before doing that work
   - keep the plan aligned with the task's acceptance criteria and non-goals

7. **Proceed with the task:**
   - work on what `task.md` describes, following `steps.md` incrementally
   - after completing each numbered step/slice from `steps.md`, stop and report the changes made, checks run, open questions, and any deviations or findings; ask the user to confirm before starting the next step
   - do not continue into the next `steps.md` step without explicit user confirmation, even if the next step seems obvious or mechanical
   - if the user has questions, requests changes, or wants to adjust scope at a step boundary, handle that before proceeding
   - if `task.md` does not name a working directory, default to the selected `/Volumes/dev/shaka/gtm/<checkout>/` when `<project>` is `gtm`; default to `/Volumes/dev/mydev/<project>/` when `<project>` starts with `my_`; otherwise default to `/Volumes/dev/shaka/<project>/`
   - only `task.md` and `steps.md` define the work — do not read other files in the task folder (e.g. `next.md`, notes, drafts) as instructions unless `task.md` explicitly references them
   - if the body is just `# Context` (or otherwise empty of instructions), ask the user what they want done before proceeding

8. **After completing the task:**
   - re-read `task.md` and `steps.md` and verify nothing was missed
   - report what was done
   - separately propose all improvements, findings, validations, edge cases, follow-up tasks, and behavior changes you noticed but intentionally did not implement because they were outside the current task/current behavior

## Important Notes

- Do not auto-use this skill without the explicit `/workit` command
- Do not create or modify task folders here except for creating/updating the selected task's `steps.md` implementation plan
- Do not modify `task.md` content unless explicitly asked
- The task folder must already exist; if it doesn't, suggest the user run `/taskit` first
