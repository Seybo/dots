---
name: autowork
description: >-
  Render the current read-only Autoimplement and Autofix status for one authored
  Task. Command-only skill.
disable-model-invocation: true
---

# Autowork status

Supported invocations:

```text
/skill:autowork --status
/autowork --status
/skill:autowork --status --task <task-id>
/autowork --status [<project-or-session>] --task <task-id>
```

Reject bare `/autowork`, duplicate flags, unsupported options, and every other
argument shape with:

```text
Usage: /autowork --status | /autowork --status [<project-or-session>] --task <task-id>
```

## Resolve the Task

Read and follow [`../components/task-resolution.md`](../components/task-resolution.md)
and the registered project configuration in
`~/.ai/skills-shared/components/projects.yml`.

Parse only these status forms after removing the command name:

1. `--status`
2. `--status --task <digits>`
3. `--status <project-or-session> --task <digits>`

Require `--status` exactly once in the first position and `--task` at most once.
Validate every explicit Task ID as digits only. Reject every other argument
shape before resolving project or Task state.

Resolve a missing project from the current checkout. Normalize an explicit
registered project or ordinal session alias through the shared rules. Resolve
the code checkout from the registry; never create or switch a checkout or
workspace.

With no explicit `--task <digits>`, inspect the resolved checkout's current
branch and infer the Task ID only from the first `sc-<digits>` branch segment.
On `main`, `master`, a local-provider Task, or any arbitrary branch without that
segment, stop with the usage text and require `--task <digits>`. Never infer a
local Task from its branch.

Resolve the numeric ID beneath `$DEV_ROOT/_tasks/<project>/`. Require exactly
one first-level Task folder whose name begins with that ID and require its
`task.md`. Stop and list the matches when ambiguous; stop with the searched task
root when none match. Never select the newest Task folder or a SQLite row.
Resolve the selected folder to its canonical absolute path.

## Show status

Shell-escape the canonical Task path and run exactly:

```text
$DEV_ROOT/bin/skills/autoimplement show-task-status <canonical-task-path>
```

Pass no project key, Task ID, checkout, branch, or other argument to the helper.
Return helper stdout unchanged.

This operation is read-only. The helper uses `Database.readonly_connection`.
Do not run migrations. Do not initialize, resume, rebase, retry, decide, squash,
or execute `Next:`. Do not modify Git, Task files, or SQLite. Do not create a
status report, history view, compatibility path, or persisted artifact.

Surface resolution, Task-file, database, and impossible-lifecycle failures
unchanged and stop.
