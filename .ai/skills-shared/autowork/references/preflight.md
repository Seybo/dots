# Preflight — doctor, task resolution, workit contract

Read this file when starting or QA-ing a run (before the Ruby helper launches).

## Doctor command

`/autowork doctor` is abstract environment health, not task QA. It does not take a project or task id. When panes are healthy, it sends one harmless "no action required" line to `agent-worker` and `agent-reviewer` so pane delivery is QA'd without repeating a second command. It may run on a dirty worktree and should report dirty/clean status instead of failing. It does not touch git state or repo files.

`/autowork doctor --no-send-test` keeps doctor fully read-only and skips the harmless tmux delivery test.

Use the seeded `my_autowork_qa` project for real end-to-end task QA with normal `/autowork my_autowork_qa 0001`; do not use `doctor` for that.

Doctor should report:

- helper path
- current repo root
- current branch
- worktree clean/dirty status
- current tmux window pane-title discovery for exact titles:
  - `agent-manager`
  - `agent-worker`
  - `agent-reviewer`
- pane IDs for each role
- whether all panes resolve to the same git root as the current repo
- status JSON validator health using a sample object
- prompt-delivery readiness

Doctor output should be human-readable and clear enough that the user can QA the shell/tmux environment from the `agent-manager` prompt.

## Task resolution

Resolve task folders the same way `/draftit`, `/taskit`, and `/workit` do, using the shared rules from:

```text
/Users/inseybo/.ai/skills-shared/components/task-resolution.md
```

`/autowork` requires the selected task folder to contain `task.md`. It infers the project from the current checkout and the task ID from an `sc-<digits>` branch segment when possible. For arbitrary branch names, pass the task ID positionally, such as `/autowork 0001`. It also requires `steps.md` before the Ruby helper starts, but `/autowork` owns a preflight that creates or updates `steps.md` through `/workit` when needed.

When starting a new autowork run (no `autowork-log/config.yml` and `state.json`), go to the related task repo root at `/Volumes/dev/_tasks/<project>/` and stage changes only from finished task folders. A task is finished when autowork state is `status: done` and `phase: complete`; an existing addressit state must also be `phase: complete`, but missing addressit state is allowed. Include `review-risk-registry.json` only when no other task has an active autowork or addressit state. Commit the selected changes with the exact message `save`; skip when there are no selected changes. Stop if staging or committing fails. Resuming an existing run does not create another task-repo save commit.

## Preflight before running the Ruby helper

1. resolve the same `<project-or-session> [task_id] [full-base-branch-or-ref]` arguments that `/autowork` will pass to the helper; treat `--retry` and `--super-review <agent>` as Autowork-only flags and never pass them to `/workit`
2. if a full base branch/ref was supplied, preserve it exactly; do not infer it from a numeric task/story ID
3. if `<task_folder>/steps.md` is missing, a base branch/ref was supplied, or branch setup/verification is needed, invoke `/workit ... create-steps-only` before the Ruby helper:
   ```text
   /workit <project-or-session> [task_id] create-steps-only
   /workit <project-or-session> [task_id] --base <full-base-branch-or-ref> create-steps-only
   ```
   Use the `--base` form when `/autowork` was invoked with a full base branch/ref. If project is inferred, pass the inferred task selector with `--base`, e.g. `/workit <task_id> --base <full-base-branch-or-ref> create-steps-only`.
4. rely on `/workit create-steps-only` to use the documented `/workit`/`/taskit` branch rules; for GTM Shortcut tasks this means the branch slug comes from the current Shortcut story `name`, fetched through the shared Shortcut CLI, not from the task folder suffix
5. if `/workit create-steps-only` stops for a branch decision, base-branch mismatch, rebase requirement, or plan problem, stop `/autowork` before running the helper and surface that decision to the user
6. after preflight succeeds, run the Ruby helper normally; the helper stores the same base as `review_base_ref` for final super-review

If `steps.md` already exists, `/autowork` may skip plan creation, but it must still not skip `/workit` branch setup/verification when a full base branch/ref was supplied. The Ruby helper also requires `steps.md` and will fail fast if the preflight did not create it.

## Required workit support

`/workit` should support creating only the steps plan:

```text
/workit <task> create-steps-only
```

Rules for `/workit ... create-steps-only`:

- read `task.md`
- perform normal project/branch setup or verification before returning to `/autowork`
- create or update `steps.md` using normal planning rules
- do not implement any step
- do not edit production code
- do not stage or commit
- stop after reporting `steps.md` path and branch status

`/workit` should also support executing exactly one planned step:

```text
/workit <task> step N
```

Rules for `/workit ... step N`:

- read `task.md`
- read `steps.md`
- treat `steps.md` as frozen
- execute only `## Step N` through before the next `## Step <number>` heading
- do not edit `steps.md` unless the step is impossible/stale, in which case stop and report
- do not commit
- leave code changes unstaged/uncommitted for `/autowork` to commit

`steps.md` must use parseable headings:

```md
## Step 1: ...
## Step 2: ...
```

`/autowork` parses steps with:

```text
^## Step ([0-9]+)\b
```
