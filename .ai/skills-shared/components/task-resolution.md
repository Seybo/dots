# Task resolution (shared)

Single source of truth for how the task-workflow skills resolve a **project**, a
**Shortcut story / task ID**, and a **code working directory** — from explicit
arguments, from the current working directory, and from the current git branch.

Used by `draftit`, `taskit`, `workit`, `sumit`, `revit`, and `pr-description-from-task`.
Those skills link here instead of restating this logic. When the rules change,
change them here only.

Runtime path (both Pi and Claude): `~/.ai/skills-shared/components/task-resolution.md`.

## Filesystem layout

- **Task folder root:** `/Volumes/dev/_tasks/<project>/` — where task definitions
  (`task.md`, `steps.md`, `draftNN/`, review artifacts) live for every project.
- **Code working directory** (where the actual repo checkout lives):
  - GTM: one of `/Volumes/dev/shaka/gtm/1st/`, `/Volumes/dev/shaka/gtm/2nd/`, or
    `/Volumes/dev/shaka/gtm/3rd/` — three equal full-clone checkouts.
  - personal projects whose name starts with `my_`: `/Volumes/dev/mydev/<project>/`.
  - all other projects: `/Volumes/dev/shaka/<project>/`.

The `<project>` name must match a first-level folder under `/Volumes/dev/_tasks/`.
Never create project roots or code checkouts automatically; only create task
folders inside an existing project folder.

## Resolving `<project>` from an explicit argument

When a skill is given `<project>` directly, resolve:

- task root → `/Volumes/dev/_tasks/<project>/`
- code working directory → the mapping above.

If the task root does not exist, stop and tell the user the project was not found.

## Inferring `<project>` from the current working directory

When `<project>` is not given, infer it from the agent's current working directory:

- inside `/Volumes/dev/shaka/gtm/1st/`, `/Volumes/dev/shaka/gtm/2nd/`, or
  `/Volumes/dev/shaka/gtm/3rd/` → project `gtm`; also remember that checkout as
  the **selected GTM checkout**.
- inside `/Volumes/dev/mydev/<project>/` → that `<project>`.
- inside `/Volumes/dev/shaka/<project>/` → that `<project>`.

## Inferring the Shortcut story ID from the current branch

Run `git -C <code-working-directory> branch --show-current` and extract the story
ID from the first branch segment matching `sc-<digits>`.

- Match with the regex `(?:^|/)sc-(\d+)(?:/|$)`; the captured digits are the story ID.
- Example: cwd `/Volumes/dev/shaka/gtm/2nd/` plus branch
  `mikhail/sc-33498/remove-company-data-from-prospects` → project `gtm`,
  selected checkout `2nd`, story ID `33498`.

An inferred story ID is handled exactly like an explicitly passed story ID; `sc-` is branch-only and must not be expected in task folder names.

## Selecting the GTM checkout

When the project is `gtm` and a code working directory is needed, choose the
checkout in this order:

1. if branch/path inference already selected a GTM checkout, use it;
2. else if the current working directory is inside one of the three checkouts, use it;
3. otherwise ask the user which checkout to use: `1st`, `2nd`, or `3rd`.

## Fallbacks

- If a required project or story ID cannot be inferred, ask the user to pass it
  explicitly rather than guessing.
- Do not fail a skill just because the code working directory does not exist on
  disk; only require it when the skill actually needs to touch the repo.
