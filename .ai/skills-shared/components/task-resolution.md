# Task resolution (shared)

Single source of truth for how the task-workflow skills resolve a **project**, a
**Shortcut story / task ID**, and a **code working directory** — from explicit
arguments, from the current working directory, and from the current git branch.

Used by `projectit`, `draftit`, `taskit`, `workit`, `sumit`, `revit`, and
`pr-description-from-task`. Those skills link here instead of restating this
logic. When the rules change, change them here only.

Runtime path (both Pi and Claude): `~/.ai/skills-shared/components/task-resolution.md`.

## Filesystem layout

- **Task folder root:** `/Volumes/dev/_tasks/<project>/` — where task definitions
  (`task.md`, `steps.md`, `draftNN/`, review artifacts) live for every project.
- **Project names:** normal task-workflow projects must start with one of these
  prefixes:
  - `my_` — personal projects
  - `shaka_` — Shaka projects
  - `misc_` — miscellaneous projects
- **GTM session aliases:** `shaka_gtm1`, `shaka_gtm2`, and `shaka_gtm3` are Zellij/session aliases, not task project roots. When accepted by a task-workflow skill, normalize them to project `shaka_gtm` and select checkout `1st`, `2nd`, or `3rd` respectively.
- **Code working directory** (where the actual repo checkout lives):
  - `shaka_gtm`: one of `/Volumes/dev/projects/shaka/gtm/1st/`,
    `/Volumes/dev/projects/shaka/gtm/2nd/`, or `/Volumes/dev/projects/shaka/gtm/3rd/` — three equal
    full-clone checkouts under the Shaka projects root.
  - `my_*`: `/Volumes/dev/projects/mydev/<project>/`.
  - `shaka_*`: `/Volumes/dev/projects/shaka/<project>/`.
  - `misc_*`: `/Volumes/dev/projects/misc/<project>/`.

For task-consuming skills, the normalized `<project>` name must match a first-level folder
under `/Volumes/dev/_tasks/`. Those skills must never create project roots or code
checkouts automatically; only `projectit` creates project roots and code working
directories.

## Resolving `<project>` from an explicit argument

When a skill is given `<project>` directly, first normalize GTM session aliases:

- `shaka_gtm1` → project `shaka_gtm`, selected GTM checkout `1st`
- `shaka_gtm2` → project `shaka_gtm`, selected GTM checkout `2nd`
- `shaka_gtm3` → project `shaka_gtm`, selected GTM checkout `3rd`

Then resolve:

- task root → `/Volumes/dev/_tasks/<normalized-project>/`
- code working directory → the mapping above, using the selected checkout when the normalized project is `shaka_gtm`.

If the task root does not exist, stop and tell the user the project was not found. Do not look for `/Volumes/dev/_tasks/shaka_gtm1`, `/Volumes/dev/_tasks/shaka_gtm2`, or `/Volumes/dev/_tasks/shaka_gtm3`; those names are session aliases only.

## Inferring `<project>` from the current working directory

When `<project>` is not given, infer it from the agent's current working directory:

- inside `/Volumes/dev/projects/shaka/gtm/1st/`, `/Volumes/dev/projects/shaka/gtm/2nd/`, or
  `/Volumes/dev/projects/shaka/gtm/3rd/` → project `shaka_gtm`; also remember that checkout
  as the **selected GTM checkout**.
- inside `/Volumes/dev/projects/mydev/<project>/` → that `<project>` when it starts with
  `my_`.
- inside `/Volumes/dev/projects/shaka/<project>/` → that `<project>` when it starts with
  `shaka_`.
- inside `/Volumes/dev/projects/misc/<project>/` → that `<project>` when it starts with
  `misc_`.

If the directory is inside one of the base roots but the inferred folder name does
not use the required prefix, ask the user to pass `<project>` explicitly rather
than guessing.

## Inferring the Shortcut story ID from the current branch

Run `git -C <code-working-directory> branch --show-current` and extract the story
ID from the first branch segment matching `sc-<digits>`.

- Match with the regex `(?:^|/)sc-(\d+)(?:/|$)`; the captured digits are the story ID.
- Example: cwd `/Volumes/dev/projects/shaka/gtm/2nd/` plus branch
  `mikhail/sc-33498/remove-company-data-from-prospects` → project `shaka_gtm`,
  selected checkout `2nd`, story ID `33498`.

An inferred story ID is handled exactly like an explicitly passed story ID; `sc-`
is branch-only and must not be expected in task folder names.

## Selecting the GTM checkout

When the project is `shaka_gtm` and a code working directory is needed, choose the
checkout in this order:

1. if an explicit GTM session alias selected a checkout (`shaka_gtm1` → `1st`, `shaka_gtm2` → `2nd`, `shaka_gtm3` → `3rd`), use it;
2. else if branch/path inference already selected a GTM checkout, use it;
3. else if the current working directory is inside one of the three checkouts, use it;
4. otherwise ask the user which checkout to use: `1st`, `2nd`, or `3rd`.

## Fallbacks

- If a required project or story ID cannot be inferred, ask the user to pass it
  explicitly rather than guessing.
- Do not fail a skill just because the code working directory does not exist on
  disk; only require it when the skill actually needs to touch the repo.
