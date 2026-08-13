---
name: autoimplement
description: >-
  Create or resume one database-backed Autoimplement Task; implement, review,
  settle, and correct every authored Task step; complete all final reviews and
  checks; and optionally squash the completed local history. Command-only skill.
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
/skill:autoimplement --retry
/skill:autoimplement <task_id> --retry
/skill:autoimplement <project-or-session> [task_id] --retry
/skill:autoimplement --super-review-agent claude|codex
/skill:autoimplement <task_id> --super-review-agent claude|codex
/skill:autoimplement <project-or-session> [task_id] --super-review-agent claude|codex
/skill:autoimplement --rebase-base
/skill:autoimplement --rebase-base <base-ref>
```

Treat `--rebase-base [<base-ref>]` as a separate explicit operation. Require the
flag exactly once with zero or one following value and reject every other
argument or control on that invocation. Resolve the Task normally, then follow
**Rebase initialized Task** without initializing or resuming it.

For normal workflow invocations, accept at most one `--retry` flag and at most
one `--super-review-agent claude|codex` pair in any position alongside an
otherwise valid invocation.
Treat `--retry` as confirmation that the previous participant or inline Manager execution has stopped.
Reject duplicate `--retry` flags. Reject duplicate `--super-review-agent` flags,
a missing agent value, and every value except exact `claude` or `codex`.
Before Task resolution on a normal invocation, remove `--retry` and
remove the flag and its value before applying the existing Task argument parser. Reject
`--base`, every other option,
and every extra argument. Do not add status, doctor, pause, limit, lock, or
timeout options. Do not expose status through `/autoimplement`; the root `/autowork` command owns status.

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

Before parsing Task selectors, detect and validate the separate `--rebase-base`
operation or extract and validate normal `--retry` and `--super-review-agent`
controls as described above. Remove the accepted control arguments, then parse
the remaining Task selector arguments as follows:

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
projects whose key starts with `my_`. Do not create, switch, rename, or push a
branch. Rebase only through the explicit **Rebase initialized Task** operation
below. Never offer or perform that operation for a local-provider Task working
on `main` or `master`.

During isolated-database development, the operator must not run Autoimplement
while an Autofix Review is active for the same project. Do not query the
separate Autofix database to enforce this temporary rule.

## Rebase initialized Task

Treat `--rebase-base [<base-ref>]` as an explicit Shortcut-Task operation. Never
run it for a local-provider Task, initialize or resume normal orchestration, or
contact a participant.

After normal project and Task resolution, run from the canonical checkout:

```text
/Volumes/dev/bin/skills/autoimplement rebase-task <canonical-task-path>
```

When a base ref was supplied, preserve it exactly and append it as the final
argument. Ruby requires the persisted Task to remain `initialized`, a clean
configured checkout, no incomplete Work Cycle, no existing Git rebase, and
ancestral active-base and Task-start boundaries. It fetches `origin`, resolves
the selected ref once, rebases without switching or pushing, and updates only
the Task starting boundary and active config fields after complete success.

When successful output contains no conflict control lines, append one blank line
and `Resolved conflicts: none.`, return the combined output, and stop. Do not run
`resume-task`.

A conflict handoff contains exactly:

```text
AutoImplementRebaseConflict <task-id>
RebaseTargetRef <target-ref>
RebaseTargetCommit <full-target-sha>
```

Read and follow
[`../../components/rebase-conflict-resolution.md`](../../components/rebase-conflict-resolution.md)
completely. It owns conflict inspection, direct versus ambiguous resolution,
chronological reporting, failure behavior, and manual abort/restart policy.
For this caller, run only this continuation command after resolving each current
set of conflicts:

```text
/Volumes/dev/bin/skills/autoimplement continue-task-rebase <canonical-task-path> <target-ref> <full-target-sha>
```

The original explicit operation named by the shared policy is
`/skill:autoimplement --rebase-base [<base-ref>]`.

## Repository final-check preflight

For a normal invocation, after resolving and validating the canonical checkout
but before invoking `initialize-task`, read
`<canonical-checkout>/.autowork.yml`. Do not run this preflight for the separate
rebase operation.

When the file exists, Agent-manager reads it and loosely confirms that its
`final_checks` directory-to-command mapping covers the authored Task's intended
area. The repository owns the mapping and commands.

When the file is missing:

1. Stop before invoking a helper, creating workflow database state, or contacting
   a participant.
2. Agent-manager discovers established commands from repository evidence such as
   `bin/check`, Gemfiles, package scripts, CI configuration, and documented test
   commands.
3. Propose exact `.autowork.yml` contents using only evidenced commands.
4. Require operator approval before creating the file.
5. After creation, add the exact repository-root pattern `/.autowork.yml` to the
   local exclude file resolved by `git rev-parse --git-path info/exclude`, unless
   that pattern is already present. Do not stage or commit `.autowork.yml`, and do
   not add it to a tracked ignore file.
6. Verify `git check-ignore .autowork.yml` succeeds and Git is otherwise clean,
   then tell the operator to re-invoke Autoimplement from the start.

Ruby never discovers final-check commands. Add no strict Ruby validator, and use
no root-`Gemfile` fallback when `.autowork.yml` is missing.

## Initialize or resume

Invoke Ruby from the canonical resolved checkout, shell-escaping the canonical
Task path:

```text
cd <canonical-checkout> && /Volumes/dev/bin/skills/autoimplement initialize-task <canonical-task-path>
```

When `--super-review-agent` is present, instead run:

```text
cd <canonical-checkout> && /Volumes/dev/bin/skills/autoimplement initialize-task <canonical-task-path> <claude|codex>
```

Pass the selection only to `initialize-task`. Do not pass it to `resume-task`,
`retry-task`, or any participant command. Pass no project key, expected checkout,
branch, Task contents, hashes, step details, prompts, or other runtime controls.

A new Task defaults to Claude when the option is omitted. An existing Task keeps
its persisted selection when the option is omitted and accepts an explicit
selection only when it matches. Surface a conflicting or unsupported selection
unchanged and stop without mutation. The operator must run the matching
application in `agent-reviewer`; never inspect that pane to infer an agent,
change providers, or fall back.

Retain the helper output and require its exact `Task: <id>` line. A first
invocation creates one initialized Task only when Git is clean. Reinvoking the
same path resumes it and may report status from a dirty tree. Surface missing
files, active-Task conflicts, checkout mismatches, branch mismatches, detached
checkout errors, database errors, and Git errors unchanged and stop.

For a normal invocation, run:

```text
cd <canonical-checkout> && /Volumes/dev/bin/skills/autoimplement resume-task <id>
```

For an invocation containing `--retry`, do not run `resume-task` on the retry
path. Run exactly:

```text
cd <canonical-checkout> && /Volumes/dev/bin/skills/autoimplement retry-task <id>
```

The retry helper must authorize redispatch before any participant message and
reuse only the agent persisted on the Task. Never derive or pass an agent on the
retry command. Then follow **Work Cycle handoff** for its returned
`AutoImplementCycle <id>`. If it reports a
dirty tree, no or multiple incomplete Work Cycles, a valid completed result, or a
transport cleanup failure, put `[MM_NTF]` first, surface the complete helper error,
and stop without contacting a participant. If tmux delivery fails after helper
authorization, likewise notify and stop; the Work Cycle remains incomplete and
requires another explicit `--retry` after the operator reconfirms the participant
is stopped.

Do not add arguments derived from the skill. On the normal path, process stdout
through **Continue helper output**, including `AutoImplementCycle <id>`,
`WaitWorkCycle <id>`, `Issue: <id>`, and `AutoImplementSquash <task-id>` controls.
Retain `Step N accepted.` progress before another control line. Continue
automatically through every authored step, every final-review gate, Manager
correction loops, final checks, and durable completion until operator input, the
optional squash question, or a failure stops the invocation.
Never retry or redispatch automatically.

## Work Cycle handoff

Whenever helper stdout contains an exact `AutoImplementCycle <id>` line:

1. Retain any Task, decision, or completed Work Cycle output before the control
   line. Do not display the control line.
2. Run `/Volumes/dev/bin/skills/autoimplement show-work-cycle <id>` and treat
   its JSON as authoritative. Do not display the JSON.
3. For `manager`/`review`, follow **Inline Manager review**. Never contact a
   participant pane for a Manager Work Cycle.
4. Otherwise require `worker`/`implementation`, `worker`/`review`, or
   `reviewer`/`review`, and map the role to the fixed pane title:
   - `worker` → `agent-worker`
   - `reviewer` → `agent-reviewer`
5. Require dynamic `$TMUX_PANE`. Resolve Manager's window with
   `tmux display-message -p -t "$TMUX_PANE" '#{window_id}'`, then run
   `tmux list-panes -t <resolved-window-id> -F '#{pane_id}\t#{pane_title}'`.
6. Select the only pane with the mapped title in that window. Fail unless there
   is exactly one. Never search another window or session, hardcode a pane ID,
   use `tmux list-panes -a`, or add pane-root checks.
7. Send only the literal participant message:

   ```text
   tmux send-keys -t <pane-id> -l 'AutoImplementCycle <id>'
   tmux send-keys -t <pane-id> Enter
   ```

8. Immediately run this command without a tool timeout and do no other
   Autoimplement work while it blocks:

   ```text
   /Volumes/dev/bin/skills/autoimplement wait-work-cycle <id>
   ```

9. Process wait stdout through **Continue helper output**.

When helper stdout contains an exact `WaitWorkCycle <id>` line, first run
`show-work-cycle <id>`. For a `manager`/`review`, do not block waiting and do not
run the review on a normal resume: begin with `[MM_NTF]`, report that the
incomplete Manager Work Cycle requires explicit `--retry`, and stop. An explicit
retry returns `AutoImplementCycle <id>` and runs the Manager review inline. For
participant roles, do not send another participant message; run the blocking
`wait-work-cycle <id>` command and process its output normally.

Separate retained completed Work Cycle blocks with one blank line. Surface
participant, result, commit, database, Git, and tmux failures unchanged after
the required Manager notification prefix. Never expose machine-control lines.

## Inline Manager review

For a persisted `manager`/`review` Work Cycle, run it inline in the current Manager conversation:

1. Require `scope: manager_review`, null step fields, and complete ordered
   `history` from `show-work-cycle`.
2. Read the complete Task files. `task.md` and `steps.md` are authoritative when
   conversation history is absent; also use live conversation context when
   available, including task creation and grilling decisions.
   Do not persist conversation transcripts.
3. Read every Work Cycle, input, produced issue, decision, and completion state
   in the complete ordered `history`.
4. Inspect the full commit range and Task diff:

   ```text
   git -C <canonical-checkout> log --oneline <starting_commit_sha>..HEAD
   git -C <canonical-checkout> diff <starting_commit_sha>..HEAD
   ```

5. Inspect relevant surrounding code and review every authored step as one
   implementation. Do not edit, stage, commit, push, switch branches, or run checks.
6. Follow `app/prompts/work_cycle.md`'s **Manager review** criteria. Use normal
   judgment over prior decisions. Do not suppress duplicate concerns merely
   because history contains a similar concern.
7. Publish one completed `manager`/`review` result with normal provenance and a
   `reported_issues` array. Write the complete payload first to:

   ```text
   /tmp/autoimplement-work-cycle-<id>.json.tmp
   ```

   Then atomically publish it with:

   ```text
   mv /tmp/autoimplement-work-cycle-<id>.json.tmp /tmp/autoimplement-work-cycle-<id>.json
   ```

8. Run `/Volumes/dev/bin/skills/autoimplement wait-work-cycle <id>` directly and
   process its stdout through **Continue helper output**.

If inline review is interrupted before publication, leave the Work Cycle
incomplete. A later normal invocation requests explicit `--retry`; retrying a
Manager review remains inline and never contacts a participant pane. Never
retry automatically.

## Continue helper output

Process helper stdout in this order:

1. Retain completed and accepted-step output before any control line.
2. For `AutoImplementCycle <id>` or `WaitWorkCycle <id>`, follow **Work Cycle
   handoff** in this invocation.
3. For an `Issue: <id>` block, follow **Issue assessment**.
4. For `AutoImplementSquash <task-id>`, follow **Optional squash**.
5. Return ordinary failed-check output without creating a Work Cycle; a normal
   later resume reruns the complete checks.
6. Surface every other failure unchanged and stop. Never retry automatically.

## Final lifecycle order

The persisted lifecycle order is:

1. independent Reviewer review for every authored step
2. one whole-task super-review
3. one whole-task Worker self-review
4. Manager-context review and its correction loops
5. final checks
6. durable completion

The super-review and Worker self-review each run exactly once. Findings from any
final review use ordinary Reported Issue Fix, Skip, or Unclear assessment.
Approved findings are batched into a nil-step Worker implementation committed as
`Final review correction N`; each correction receives a scoped independent
Reviewer pass over exactly `git diff HEAD~1..HEAD`. A clean or skipped-only
scoped pass after a Manager correction starts a fresh Manager review with the
complete updated history. Corrections never rerun either one-time whole-task
gate. Do not suppress duplicate concerns; rely on Manager judgment.

The super-review uses the persisted agent and exact
`Task.starting_commit_sha..HEAD` range. Its `super-review.md` is temporary and
non-authoritative: remove it before result publication, never commit it, and
store no raw candidates or adjudication prose in SQLite.

A clean or all-skipped Manager pass runs final checks. Failed or interrupted
checks leave the Task in `manager_review`; normal resume reruns the full check
set without another Manager review. Passing checks on clean Git persist only
`final_checks_passed`. Stable terminal resume returns completion without checks,
Git inspection, a new Work Cycle, or another squash offer. Autoimplement never
pushes.

## Optional squash

When stdout contains `AutoImplementSquash <task-id>`, the Task is already
durably complete. Retain and display all other completion output, but never
display the control line.

1. Briefly inspect the complete local range:

   ```text
   git -C <canonical-checkout> log --oneline <starting_commit_sha>..HEAD
   git -C <canonical-checkout> diff <starting_commit_sha>..HEAD
   ```

2. Confirm by Manager judgment that the range belongs to the Task. If anything
   looks unrelated, missing, suspicious, or outside intended scope, begin with
   `[MM_NTF]`, ask the operator about it, and do not offer or run squash yet.
   Do not validate commit subjects or counts against SQLite.
3. Resolve the subject before asking:
   - For `task_provider: shortcut`, use the resolved numeric Task folder ID as
     the attached story ID. Follow the shared Shortcut skill and run its
     `get-story` command, preferring:

     ```text
     ruby ~/.pi/agent/extensions/shortcut/scripts/shortcut.rb get-story <story-id>
     ```

     Use the current Shortcut story name exactly. If lookup or name extraction
     fails, abort without fallback or Git mutation.
   - For `task_provider: local`, derive
     `Task <task-id>: <folder slug as words>` from the canonical Task folder,
     removing its leading numeric ID and converting slug separators to spaces.
4. Ask exactly:

   ```text
   [MM_NTF] Should i squash?
   ```

Do not persist the question, answer, pending state, or squash result. For the
operator's next reply while the question is active:

- Treat `yes`, `go`, `squash`, `approve`, or `approved` as approval and run:

  ```text
  /Volumes/dev/bin/skills/autoimplement squash-task <task-id> <canonical-checkout> <subject>
  ```

- Treat `no`, `skip`, or `leave` as declining. Run no helper and report that the
  Task commits remain unchanged.
- A question or unrelated message is not an answer. Answer it without invoking
  the helper, then ask `[MM_NTF] Should i squash?` again.

Return squash success or failure unchanged. A failure, decline, or successful
squash leaves durable Task state unchanged. Never resume, persist squash
metadata, push, or automatically retry.

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
Treat the next reply as clarification, including `yes` or `go`, and reassess the
same issue. Follow the shared decision-reason policy: when the clarification
makes Fix or Skip unambiguous and supplies its factual basis, apply its
understanding and agreement rules; otherwise ask one precise decision question.

## Decisions

Read and follow
[`../../components/reported-issue-decision-reasons.md`](../../components/reported-issue-decision-reasons.md)
completely. It owns reason retention, acceptance, contrary decisions, safe
helper arguments, and exact stored output. Use the mappings below to identify
the requested outcome; persist it only when the shared policy has a reason.

Use the currently assessed issue ID for the operator's next clear decision:

- `fix`, `approve`, or `approved` → `approved`
- `skip`, `ignore`, `reject`, or `invalid` → `skipped`
- any unambiguous affirmative response to the current recommendation—including
  `go`, `yes`, `ok`, `okay`, `accept`, `approved`, or equivalent clear language—
  accepts it: Fix becomes `approved` and Skip becomes `skipped`
- `yes` or `go` answering an Unclear question is clarification; reassess it and
  apply the shared policy before deciding whether anything can be persisted
- questions, details requests, clarifications, and unrelated messages are not
  decisions

For genuine ambiguity, begin with `[MM_NTF]`, name the Reported Issue ID, and
ask one precise question without persisting anything.

For one clear decision with its required reason, run exactly one command:

```text
/Volumes/dev/bin/skills/autoimplement store-decision <id> <approved|skipped> <shell-escaped-reason>
```

Preserve the helper's exact stored `Decision:` and `Reason:` lines. Process the
remaining decision-command stdout through **Continue helper output**, retaining
accepted-step or completed Work Cycle output before its next control. Process
only one decision per operator reply. Do not refetch Task input, run Worker
classification, or start debate.

SQLite is authoritative for generated workflow state. Do not create Task logs,
review reports, or other durable generated artifacts. Structured result files
are temporary transport owned by the Work Cycle protocol. Manager remains the
only workflow database writer. Autoimplement never pushes.
