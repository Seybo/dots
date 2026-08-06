---
name: autoimplement
description: >-
  Create or resume one database-backed Autoimplement Task and run one Worker
  implementation Work Cycle for its next authored step. Command-only skill.
disable-model-invocation: true
---

# Autoimplement

Helper:

```text
/Volumes/dev/bin/skills/autoimplement
```

Supported invocations:

```text
/skill:autoimplement
/skill:autoimplement <task_id>
/skill:autoimplement <project-or-session> [task_id]
```

Reject `--base`, retry, pause, limits, and every other option or extra argument.
Do not expose a root `/autowork2` command.

## Resolve the authored Task

Read and follow `~/.ai/skills-shared/components/task-resolution.md` and the
registered project configuration in
`~/.ai/skills-shared/components/projects.yml`. The skill owns all project,
workspace, Task-folder, and protected-branch resolution. Do not invoke or port
legacy Autowork's Ruby `ProjectRegistry` or `TaskResolver`.

Parse arguments as follows:

1. With no arguments, infer the registered project and workspace from the
   current checkout. Infer a Task ID only from an `sc-<digits>` branch segment.
2. With one argument:
   - when it is a registered project or session alias, select that project and
     workspace, then infer an `sc-<digits>` Task ID when available
   - otherwise require digits only, infer the project and workspace from the
     current checkout, and use the argument as the Task ID
3. With two arguments, require the first to be a registered project or session
   alias and the second to be a digits-only Task ID.
4. Reject every other argument shape. Never guess a project, workspace, or Task
   from an arbitrary branch name.

For an ordinal project without an explicit session alias, use the workspace
containing the current directory when available; otherwise ask the operator to
select the workspace. Resolve a direct project to its registered checkout.
Never create a checkout or task root.

When no Task ID can be inferred, list the 10 most recent first-level Task
folders under `/Volumes/dev/_tasks/<project>/`:

- prefer filesystem creation/birth time, then modification time, then folder
  name ordering
- include a numbered selection, folder name, and first meaningful Markdown
  heading or non-empty line from `task.md`
- accept the next operator reply as either the displayed selection number or a
  digits-only Task ID

Resolve a Task ID by matching first-level folders beginning with that ID.
Require exactly one match and require the folder to contain `task.md`. Stop and
list matches when ambiguous; stop with the searched task root when none match.
Resolve the selected folder to its canonical absolute path.

## Validate authored inputs and branch

Require both `task.md` and `steps.md` in the selected Task folder. Require
`steps.md` to contain at least one line matching:

```text
^## Step ([0-9]+)\b
```

If either file or the canonical step heading is missing, stop and tell the
operator to run `/workit <task_id>`, approve the plan, and invoke
`/autoimplement` again. Never invoke Workit automatically.

Run `git -C <canonical-checkout> branch --show-current` and require a non-empty
branch. Refuse `main` and `master`, except for project `env` and registered
projects whose key starts with `my_`. Do not create, switch, rename, rebase, or
push a branch.

During isolated-database development, the operator must not run Autoimplement
while an Autofix Review is active for the same project. Do not query the
separate Autofix database to enforce this temporary rule.

## Initialize or resume

Invoke Ruby from the canonical resolved checkout, shell-escaping the canonical
Task path:

```text
cd <canonical-checkout> && /Volumes/dev/bin/skills/autoimplement initialize-task <canonical-task-path>
```

Pass only the canonical Task path. Do not pass a project key, expected checkout,
branch, Task contents, hashes, step details, prompts, or runtime controls.

Retain the helper output and require its exact `Task: <id>` line. A first
invocation creates one initialized Task only when Git is clean. Reinvoking the
same path resumes it and may report status from a dirty tree. Surface missing
files, active-Task conflicts, checkout mismatches, branch mismatches, detached
checkout errors, database errors, and Git errors unchanged and stop.

Run:

```text
cd <canonical-checkout> && /Volumes/dev/bin/skills/autoimplement resume-task <id>
```

Do not add arguments derived from the skill. Follow **Work Cycle handoff** when
stdout is `AutoImplementCycle <id>` or `WaitWorkCycle <id>`. Return
`No unimplemented Task step.` unchanged.

## Work Cycle handoff

When stdout is exactly `AutoImplementCycle <id>`:

1. Require the dynamic `$TMUX_PANE` value for Manager's pane. Resolve its window
   with `tmux display-message -p -t "$TMUX_PANE" '#{window_id}'`, then run
   `tmux list-panes -t <resolved-window-id> -F '#{pane_id}\t#{pane_title}'`.
2. Select the only pane titled `agent-worker` in that window. Fail unless there
   is exactly one. Never search another window or session, hardcode a pane ID,
   use `tmux list-panes -a`, or add pane-root checks.
3. Send only the literal participant message:

   ```text
   tmux send-keys -t <pane-id> -l 'AutoImplementCycle <id>'
   tmux send-keys -t <pane-id> Enter
   ```

4. Immediately run the following command without a tool timeout and perform no
   other Autoimplement work while it blocks:

   ```text
   /Volumes/dev/bin/skills/autoimplement wait-work-cycle <id>
   ```

5. Return the retained Task output followed by the wait-command output. Do not
   display the `AutoImplementCycle` control line.

When stdout is exactly `WaitWorkCycle <id>`, do not send another tmux message.
Run the same blocking `wait-work-cycle` command without a tool timeout and
return its output with the retained Task output.

Surface participant, result, commit, database, Git, and tmux failures unchanged
and stop. Do not retry or redispatch. This checkpoint stops after one completed
Worker implementation Work Cycle; it does not start review or another step.

SQLite is authoritative for generated workflow state. Do not create Task logs,
reports, or other durable artifacts. Structured result files are temporary
transport owned by the Work Cycle protocol. Autoimplement never pushes.
