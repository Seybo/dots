---
name: autoimplement
description: >-
  Create or resume one database-backed Autoimplement Task and implement, review,
  settle, and correct every authored Task step. Command-only skill.
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

## Operator attention notifications

Begin the complete operator-facing turn with `[MM_NTF]` whenever Autoimplement
cannot continue without operator input or action. This includes:

- every Fix, Skip, or Unclear Reported Issue assessment
- clarification questions and genuine decision ambiguity
- participant, Work Cycle, helper, Git, database, or tmux failures that require
  operator direction

When retained progress and a blocking request share one turn, put `[MM_NTF]`
before the retained progress. Do not prefix normal progress, successful step
acceptance, participant messages, or machine-control lines such as
`AutoImplementCycle <id>` and `WaitWorkCycle <id>`.

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
stdout contains `AutoImplementCycle <id>` or `WaitWorkCycle <id>`. Follow
**Issue assessment** when stdout contains an `Issue: <id>` block. Retain
`Step N accepted.` progress before another control line. Continue automatically
through every authored step until operator input, `No unimplemented Task step.`,
or a failure stops the invocation.

## Work Cycle handoff

Whenever helper stdout contains an exact `AutoImplementCycle <id>` line:

1. Retain any Task, decision, or completed Work Cycle output before the control
   line. Do not display the control line.
2. Run `/Volumes/dev/bin/skills/autoimplement show-work-cycle <id>` and treat
   its JSON as authoritative. Read its persisted `role` and `action`; do not
   display the JSON.
3. Require either `worker`/`implementation` or `reviewer`/`review`. Map the role
   to the fixed pane title:
   - `worker` → `agent-worker`
   - `reviewer` → `agent-reviewer`
4. Require the dynamic `$TMUX_PANE` value for Manager's pane. Resolve its window
   with `tmux display-message -p -t "$TMUX_PANE" '#{window_id}'`, then run
   `tmux list-panes -t <resolved-window-id> -F '#{pane_id}\t#{pane_title}'`.
5. Select the only pane with the mapped title in that window. Fail unless there
   is exactly one. Never search another window or session, hardcode a pane ID,
   use `tmux list-panes -a`, or add pane-root checks.
6. Send only the literal participant message:

   ```text
   tmux send-keys -t <pane-id> -l 'AutoImplementCycle <id>'
   tmux send-keys -t <pane-id> Enter
   ```

7. Immediately run the following command without a tool timeout and perform no
   other Autoimplement work while it blocks:

   ```text
   /Volumes/dev/bin/skills/autoimplement wait-work-cycle <id>
   ```

8. If wait stdout contains another `AutoImplementCycle <id>` line, retain its
   completed and accepted-step output, then repeat this handoff in the same
   invocation. Do not pause between authored steps.
9. Otherwise follow **Issue assessment** when stdout contains an `Issue: <id>`
   block. Return retained output through `No unimplemented Task step.` after the
   final accepted step. Stop on any failure. Do not retry or redispatch.

When helper stdout contains an exact `WaitWorkCycle <id>` line, do not send
another participant message. Run the same blocking `wait-work-cycle` command
without a tool timeout. Process its output through the same repeated-handoff,
issue-assessment, final no-step, or failure rules above.

Separate retained completed Work Cycle blocks with one blank line. Surface
participant, result, commit, database, Git, and tmux failures unchanged after
the required Manager notification prefix. Never expose machine-control lines.

## Issue assessment

Whenever helper stdout contains an `Issue: <id>` block, treat the ID and quoted
stored body as Manager handoff data.

1. Retain the ID and complete stored body.
2. Read `../app/prompts/assess_issue.md` from the shared package.
3. Inspect only relevant current project code, the authored Task, and existing
   conversation context. Do not edit files or run tests, linters, or formatters.
4. Follow the prompt and present its concise assessment. With retained progress,
   put `[MM_NTF]` first, then the progress, one blank line, and the assessment
   beginning at `Issue <id>` without repeating the prefix.
5. Treat the recommendation as advisory. Do not persist a decision, create a
   Work Cycle, or contact a participant until the operator clearly decides.

If the operator asks for details, begin with `[MM_NTF]`, answer without recording
a decision, and request the still-needed decision.

For an `Unclear` recommendation, ask one precise question and persist nothing.
Treat the next reply as clarification, including `yes` or `go`; reassess the
same issue and request a separate clear decision. Only an explicit `fix` or
`skip` in that clarification reply is also a decision.

## Decisions

Use the currently assessed issue ID for the operator's next clear decision:

- `fix`, `approve`, or `approved` → `approved`
- `skip`, `ignore`, `reject`, or `invalid` → `skipped`
- `yes` or `go` accepts the current recommendation: Fix becomes `approved` and
  Skip becomes `skipped`
- `yes` or `go` for Unclear is clarification only and persists nothing
- questions, details requests, clarifications, and unrelated messages are not
  decisions

For genuine ambiguity, begin with `[MM_NTF]`, name the Reported Issue ID, and
ask one precise question without persisting anything.

For one clear decision, run exactly one command:

```text
/Volumes/dev/bin/skills/autoimplement store-decision <id> <approved|skipped>
```

When stdout contains `AutoImplementCycle <id>`, retain any accepted-step output
and follow **Work Cycle handoff**, continuing through later authored steps.
Otherwise follow **Issue assessment** for the next issue or return the final
`No unimplemented Task step.` output. Process only one decision per operator
reply. Do not refetch Task input, run Worker classification, or start debate.

SQLite is authoritative for generated workflow state. Do not create Task logs,
review reports, or other durable generated artifacts. Structured result files
are temporary transport owned by the Work Cycle protocol. Manager remains the
only workflow database writer. Autoimplement never pushes.
