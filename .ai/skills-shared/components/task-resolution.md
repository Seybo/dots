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
- **Project names:** normal task-workflow projects must start with `my_`, `shaka_`,
  or `misc_`.
- **Project registry:** `~/.ai/skills-shared/components/projects.yml` is the source
  of truth for each project's code root, layout, and task provider.
- **Task providers:** `task_provider: shortcut` permits Shortcut story and branch
  workflows; `task_provider: local` is local/manual-only and is the default for new
  projects.
- **Normal code working directory:** every normal project checkout is an ordinal
  workspace below its registered code root:
  ```text
  /project/1st/
  /project/2nd/
  /project/7th/
  /project/28th/
  ```
  `1st` is required; any positive ordinal is valid, and additional workspaces do
  not need to be provisioned in advance.
- **Session aliases:** `<project><number>` selects the matching ordinal workspace:
  `shaka_trp1` → `1st`, `shaka_trp7` → `7th`, and `shaka_trp28` → `28th`.
  These aliases are session names, not task project roots.
- **Infrastructure exception:** `env` maps directly to `/Users/inseybo/.dots/` and
  is not moved below an ordinal workspace.

For task-consuming skills, the normalized `<project>` name must match a first-level folder
under `/Volumes/dev/_tasks/`. The project registry must contain the project before a
skill touches its code checkout. Task-consuming skills must not create code checkouts
automatically.

## Resolving `<project>` from an explicit argument

When a skill is given `<project>` directly, first match a trailing positive number
against a registered project name. Normalize the number to its canonical ordinal suffix:

- `shaka_gtm1` → project `shaka_gtm`, workspace `1st`
- `shaka_trp7` → project `shaka_trp`, workspace `7th`
- `shaka_trp28` → project `shaka_trp`, workspace `28th`

Then resolve:

- task root → `/Volumes/dev/_tasks/<normalized-project>/`
- code working directory → `<registered-code-root>/<ordinal>/`
- `env` → `/Users/inseybo/.dots/`

If the task root does not exist, stop and tell the user the project was not found.
Do not look for session aliases as task roots.

## Inferring `<project>` from the current working directory

When `<project>` is not given, match the current directory against registered code roots.
The first path component below a normal code root must be a canonical ordinal workspace;
that workspace is selected for the task. A directory at the code root itself is ambiguous
and must not be treated as a checkout.

The `env` project is inferred from `/Users/inseybo/.dots/`.

## Inferring the Shortcut story ID from the current branch

Run `git -C <code-working-directory> branch --show-current` and extract the story
ID from the first branch segment matching `sc-<digits>`.

- Match with the regex `(?:^|/|^)sc-(\d+)(?:/|$)`; the captured digits are the story ID.
- Example: cwd `/Volumes/dev/projects/shaka/trp/28th/` plus branch
  `mikhail/sc-33498/report-warning` → project `shaka_trp`, workspace `28th`,
  story ID `33498`.

An inferred story ID is handled exactly like an explicitly passed story ID; `sc-`
is branch-only and must not be expected in task folder names.

## Selecting a workspace

Choose the workspace in this order:

1. an explicit `<project><number>` session alias;
2. workspace inferred from the current working directory;
3. ask the user for a positive workspace number.

Convert numbers using normal ordinal rules: `11th`, `12th`, and `13th` use `th`; otherwise
`1st`, `2nd`, and `3rd` use their suffixes and all other numbers use `th`.
## Optional base branch/ref for stacked task branches

Task-workflow skills that create or verify task branches (`taskit`, `workit`, and
`autowork` preflight through `workit`) may accept an explicit full base branch/ref
for stacked work.

Rules:

- The base branch/ref is a full Git ref string such as
  `origin/team/sc-111/parent-task` or `team/sc-111/parent-task`.
- Do not infer a base from a numeric task/story ID. If the base is not `main` or
  `master`, the user must pass the whole branch/ref.
- The base branch/ref is used for branch creation/verification and, for
  `/autowork`, for final super-review diff scope.
- Do not rely on Git upstream/tracking branch as the task's base. Upstream is
  normally the branch's push/pull target and can change after `git push -u`.
  When creating a task branch from an explicit remote base, use `git checkout
  --no-track -b <branch-name> <base_ref>` so Git does not set the parent/base
  branch as the new branch's upstream.
- If an explicit base branch/ref is given and existing branch state contradicts it,
  stop and report the mismatch instead of silently switching bases.
- If the parent/base branch has advanced and the task branch needs a rebase, stop
  and ask for explicit approval before rebasing; rebase rewrites commit history.
- For `/autowork`, record the exact base commit at run setup. If the base ref later
  resolves to a different commit, pause before starting more work. After the user
  intentionally rebases or changes the task base, update the recorded base with
  `autowork update-base <task_folder> <new-base-ref>`.

## Fallbacks

- If a required project or story ID cannot be inferred, ask the user to pass it
  explicitly rather than guessing.
- Do not fail a skill just because the code working directory does not exist on
  disk; only require it when the skill actually needs to touch the repo.
