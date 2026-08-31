# Task resolution (shared)

Single source of truth for resolving a task project, task ID, and code checkout.
Used by task-workflow skills including `draftit`, `taskit`, `workit`, `sumit`,
`autowork`, `autoimplement`, `autofix`, `addressit`, and PR-description/review
tooling.

Runtime files:

- registry: `~/.ai/skills-shared/components/projects.yml`
- task root: `$DEV_ROOT/_tasks/<project>/`
- helper commands: `$DEV_ROOT/bin/skills/`

## Development root

`DEV_ROOT` is the machine's development tree. Squirrel uses `/Volumes/dev`;
Oma uses `/home/svin/dev`.

Registry paths beginning with `/` are absolute. Expand paths beginning with `~`
against the current user's home. Resolve every other `checkout_path` or
`code_root` relative to `DEV_ROOT`. Prefer relative registry paths for projects
beneath `DEV_ROOT` so the registry remains portable.

## Project registry

`projects.yml` is the source of truth. Project keys are friendly local names:
they must start with a lowercase letter and may contain lowercase letters,
digits, `_`, and `-`. The key is also the task-root directory name.

Every project has a `checkout_layout` and defaults to `task_provider: local`.

### Direct checkout

Use `direct` for an existing standalone checkout, including an ad-hoc GitHub
clone:

```yaml
rails:
  checkout_layout: direct
  checkout_path: oss/rails
  task_provider: local
```

Any directory inside `checkout_path` resolves to `rails`; the code working
directory is exactly `checkout_path`. A direct project has one checkout path.
To relocate or reclone it, update `checkout_path` manually.

### Ordinal workspaces

Use `ordinal_workspaces` for the existing multi-checkout layout:

```yaml
shaka_gtm:
  checkout_layout: ordinal_workspaces
  code_root: projects/shaka/gtm
  task_provider: shortcut
```

Checkouts live below `code_root` in canonical ordinal folders such as `1st`,
`2nd`, and `28th`. A session alias selects one workspace:

```text
shaka_gtm2 -> project shaka_gtm, workspace 2nd
```

`env` is a direct infrastructure project mapped to `~/.dots`.

## Registering a direct project

Registration is manual. Do not infer a project from a Git remote or mutate the
registry automatically. Add a direct entry to `projects.yml` with the friendly
name and checkout path you choose.

On first `/taskit` or `/draftit` use for a registered project, create its
missing task root at `$DEV_ROOT/_tasks/<project>/`. Task-consuming/reporting
skills never create missing task roots.

## Resolving a project

1. An explicit project argument uses the matching registry key. Ordinal session
   aliases are valid only for `ordinal_workspaces` projects.
2. Without an explicit project, match the current directory against registered
   checkout paths. A direct checkout resolves to its root. An ordinal checkout
   resolves to the canonical ordinal folder below its code root.
3. If no project matches, stop and ask the user to register the checkout in
   `projects.yml` or pass a registered project explicitly. Do not guess.

An explicit project maps to `$DEV_ROOT/_tasks/<project>/`. A direct project
needs no workspace selection. An ordinal project selects a workspace in this
order: explicit session alias, workspace inferred from the current directory,
then user input.

## Task selection

Task folders remain directly below the project task root:

```text
$DEV_ROOT/_tasks/<project>/<task-id>-<slug>/
```

Local/manual tasks use zero-padded four-digit IDs such as `0001`. Shortcut
projects use Shortcut story IDs. Select a task explicitly by its numeric ID,
which is matched as a folder prefix:

```text
/workit 0001
/autoimplement 0001
/autowork --status --task 0001
/autofix --local --task 0001
```

`/autowork` is read-only Task status. `/autoimplement` owns autonomous Task
implementation. `/autofix` owns imported GitHub or local Review work.

When the project can be inferred from the current direct checkout, the project
name is not needed. Branch inference remains a convenience only for branches
with an `sc-<digits>` segment. Do not infer a local task from an arbitrary
branch name.

When a workflow needs task context but the current branch has no inferable Task
ID, use that workflow's explicit selector: Autoimplement accepts a positional
numeric Task ID, while Autowork status and local Autofix use `--task <digits>`.
Resolve the selector exactly like any other Task identifier: require one
matching Task folder and its `task.md`; never guess from the branch name or from
the newest Task.

## Optional Features

A Feature groups related drafts and Tasks within one registered project while
keeping their folders flat. Features are optional; existing and simple drafts
and Tasks remain unfeatured.

Feature files live at:

```text
$DEV_ROOT/_tasks/<project>/features/<feature-slug>.md
```

`<feature-slug>` follows Draftit's slug rules and matches
`^[a-z][a-z0-9-]*$`. A featured draft or Task starts with this exact first line,
before `# Story details` or any other content:

```md
Feature: [<feature-slug>](../features/<feature-slug>.md)
```

The relative path is stable because draft and numbered Task folders remain
direct children of `$DEV_ROOT/_tasks/<project>/`. Never nest those folders below
`features/`.

A Feature file contains its stable shared brief and this final first-level
inventory section:

```md
# Drafts and tasks

- [draft01](../draft01/task.md)
- [0001-example-task](../0001-example-task/task.md)
```

Keep inventory links in approved work order. Draftit appends a draft only after
creating its `task.md`; Taskit replaces that link after successfully renaming
the draft folder. The Task reference is authoritative for Feature membership;
the Feature inventory is an automatically maintained index. Do not scan Feature
files to infer membership. Shared Feature context supplies the goal, scope, and
constraints, while task-specific `task.md` and `steps.md` content wins when the
texts conflict.

When a workflow uses authored Task intent, inspect the exact first line for the
Feature reference. After detecting it, resolve the link relative to the Task
folder and read the complete Feature file before using the complete `task.md` or
`steps.md` as task-specific instructions. Use the Feature goal, scope, and shared
constraints as background; do not treat its inventory as Task requirements or
copy that inventory into derived output. A normal read failure may stop the
workflow without custom recovery. When the exact reference is absent, do not
load Feature context and preserve existing unfeatured behavior.

## Local task branch rules

For `task_provider: local`, task skills use the currently checked-out branch.
They do not infer, create, rename, or switch branches. Refuse `main` and
`master` for local/ad-hoc work, except:

- `env` may use either branch.
- Any registered project whose project key starts with `my_` may use either branch.

Local Task config ownership and timing are defined in
[`task-branch-config.md`](task-branch-config.md). Taskit and Workit must read it
completely before recording branch metadata.

## Shortcut story ID inference

For Shortcut projects, extract the first branch segment matching `sc-<digits>`:

```text
mikhail/sc-33498/report-warning -> 33498
```

An inferred story ID is handled like an explicit task ID. `sc-` is branch-only;
task folders use the numeric ID without that prefix.

## Optional base branch/ref for stacked task branches

Task-workflow skills that create or verify Shortcut task branches may accept an
explicit full base branch/ref. Shared base selection, ancestry validation,
branch creation, and config persistence are defined in
[`task-branch-config.md`](task-branch-config.md). Read it completely; do not
restate or override those rules in task-resolution callers.

## Safety fallbacks

- Never create code checkouts automatically.
- Never guess an unregistered project or an arbitrary-branch task mapping.
- Stop on ambiguous task-folder prefix matches.
- Registered direct projects default to `task_provider: local`; Shortcut is an
  explicit registry choice.
