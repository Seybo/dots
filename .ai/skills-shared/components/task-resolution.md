# Task resolution (shared)

Single source of truth for resolving a task project, task ID, and code checkout.
Used by task-workflow skills including `draftit`, `taskit`, `workit`, `sumit`,
`autowork`, `addressit`, and PR-description/review tooling.

Runtime files:

- registry: `~/.ai/skills-shared/components/projects.yml`
- task root: `/Volumes/dev/_tasks/<project>/`

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
  checkout_path: /Volumes/dev/oss/rails
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
  code_root: /Volumes/dev/projects/shaka/gtm
  task_provider: shortcut
```

Checkouts live below `code_root` in canonical ordinal folders such as `1st`,
`2nd`, and `28th`. A session alias selects one workspace:

```text
shaka_gtm2 -> project shaka_gtm, workspace 2nd
```

`env` is a direct infrastructure project mapped to `/Users/inseybo/.dots`.

## Registering a direct project

Registration is manual. Do not infer a project from a Git remote or mutate the
registry automatically. Add a direct entry to `projects.yml` with the friendly
name and checkout path you choose.

On first `/taskit` or `/draftit` use for a registered project, create its
missing task root at `/Volumes/dev/_tasks/<project>/`. Task-consuming/reporting
skills never create missing task roots.

## Resolving a project

1. An explicit project argument uses the matching registry key. Ordinal session
   aliases are valid only for `ordinal_workspaces` projects.
2. Without an explicit project, match the current directory against registered
   checkout paths. A direct checkout resolves to its root. An ordinal checkout
   resolves to the canonical ordinal folder below its code root.
3. If no project matches, stop and ask the user to register the checkout in
   `projects.yml` or pass a registered project explicitly. Do not guess.

An explicit project maps to `/Volumes/dev/_tasks/<project>/`. A direct project
needs no workspace selection. An ordinal project selects a workspace in this
order: explicit session alias, workspace inferred from the current directory,
then user input.

## Task selection

Task folders remain directly below the project task root:

```text
/Volumes/dev/_tasks/<project>/<task-id>-<slug>/
```

Local/manual tasks use zero-padded four-digit IDs such as `0001`. Shortcut
projects use Shortcut story IDs. Select a task explicitly by its numeric ID,
which is matched as a folder prefix:

```text
/workit 0001
/autowork 0001
```

When the project can be inferred from the current direct checkout, the project
name is not needed. Branch inference remains a convenience only for branches
with an `sc-<digits>` segment. Do not infer a local task from an arbitrary
branch name.

## Local task branch rules

For `task_provider: local`, task skills use the currently checked-out branch.
They do not infer, create, rename, or switch branches. Refuse `main` and
`master` for local/ad-hoc work, except:

- `env` may use either branch.

`/autowork` records the branch, its initial `HEAD` SHA, and the review-base ref
and SHA at run initialization.

## Shortcut story ID inference

For Shortcut projects, extract the first branch segment matching `sc-<digits>`:

```text
mikhail/sc-33498/report-warning -> 33498
```

An inferred story ID is handled like an explicit task ID. `sc-` is branch-only;
task folders use the numeric ID without that prefix.

## Optional base branch/ref for stacked task branches

Task-workflow skills that create or verify Shortcut task branches may accept an
explicit full base branch/ref. Do not infer it from a task ID. Preserve it
exactly, verify it resolves to a commit, and record it as the review base for
`/autowork`. Do not use Git upstream as the task base.

If a recorded base moves, stop for explicit rebase/base-change instructions.
`/autowork` owns updating its recorded base after an intentional change.

## Safety fallbacks

- Never create code checkouts automatically.
- Never guess an unregistered project or an arbitrary-branch task mapping.
- Stop on ambiguous task-folder prefix matches.
- Registered direct projects default to `task_provider: local`; Shortcut is an
  explicit registry choice.
