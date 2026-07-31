---
name: guideit
description: >-
  Guide the user through a mobile-friendly review of the unstaged changes present
  when the command starts, one logical change at a time, then stage approved
  changes with explicit permission. Command-only skill. Invoke only via
  /skill:guideit.
disable-model-invocation: true
---

# Guideit

Review the unstaged work from a completed `/workit` step without making the user read a Git diff. Explain one logical change at a time in simple terms, resolve feedback, and stage the approved work only with explicit permission.

## Invocation

Use only:

```text
/skill:guideit
```

The invocation starts one interactive walkthrough. Do not auto-use this skill from an ordinary request to explain or review changes.

## Review set

At invocation, capture a fixed review set containing every unstaged tracked change and every untracked file in the code working directory.

1. Prefer the code working directory and task context already established by `/workit` in the same conversation. If that context is unavailable, use the current Git repository and available user context; ask one concise question only when the intended work cannot otherwise be identified.
2. Inspect:
   - `git status --short`
   - the unstaged diff against the index
   - untracked files reported by Git
3. Read the changed code and only the surrounding code needed to explain its behavior accurately.
4. Use the current `task.md`, `steps.md`, and completed-step context when they are already known. Do not scan unrelated task folders to reconstruct context.
5. Exclude changes that were already staged when `/guideit` started.
6. If the review set is empty, report that there are no unstaged changes to guide and stop.

Keep the initial review set fixed for the entire walkthrough. Build and retain an ordered queue from that snapshot. Do not rescan or verify Git state while walking the queue. If the user stages files manually during the walkthrough, continue with the next queued item without checking Git.

Code changes made in response to the user's feedback remain part of the logical item being discussed, including any files created by that update.

## Step 0: unrelated changes

Compare the review set with the current task and completed `/workit` step. Handle changes unrelated to that work before explaining related changes.

Present all unrelated work as **Step 0**, split into coherent groups when needed. Explain one group at a time and ask the user to choose:

- **cancel** — permanently discard that group
- **commit** — preserve that group in a separate focused commit

Both choices belong only to the user:

- Before canceling, show the exact paths, state that the action permanently discards their unstaged contents, and wait for explicit confirmation for that group. Preserve any already staged version of a tracked file. Treat deletion of an untracked file as destructive and require the same explicit confirmation.
- Before committing, propose a focused commit subject and exact paths, then wait for explicit approval. Commit only those paths without including other staged or unstaged work.
- Never infer approval from the `/guideit` invocation or from approval of another group.

After resolving Step 0, continue through the original queue of related logical changes. Do not run a Git-state verification between items.

## Build the walkthrough

Group related files by logical behavior, not by file. Order groups by dependency and cause-and-effect so later behavior builds on earlier behavior. Keep implementation, callers, configuration, specs, and documentation together when they describe the same behavior.

For each group, show:

```text
### Change N of M: <component or behavior>

File: <one primary relative path>

- <plain-language purpose>
- <important behavior>
- <important validation, safeguard, side effect, or test coverage when applicable>

Approve, explain, or update?
```

Rules:

- Use 2–5 short bullets.
- Explain what changed, why it exists, and how the pieces work together.
- Mention the component or service name and one primary file path.
- Do not narrate the diff file by file.
- Do not show diffs, line numbers, or code snippets unless the user asks.
- Do not claim behavior that is not supported by the reviewed code.
- Ask about one logical change at a time and wait for the user's reply.

## Interpret replies naturally

Do not require exact keywords. Infer these actions from normal replies:

- **approve** — mark the current logical change approved and show the next queued item; replies such as `good`, `clear`, and `continue guide` can mean approval when context makes that clear
- **explain** — answer the question or explain the same item more simply, then ask again whether it is approved or needs an update
- **update** — pause the walkthrough, make the requested code change, and re-present the same logical item before continuing

If an update request is ambiguous, ask one concise clarification before editing. Do not advance until the current item is approved.

The user may stage files manually at any point. Treat `continue guide` as an instruction to continue through the fixed queue; do not inspect or verify whether staging occurred.

## Checks

Do not run specs, tests, linters, formatters, type checks, or other verification commands. `/workit` owns checks at the end of its process.

## Final staging

After every related logical change is approved:

1. Show the exact reviewed paths that remain eligible for staging. Exclude Step 0 work that was canceled or committed separately.
2. Ask exactly:

   ```text
   All changes approved. Stage these files?
   ```

3. Wait for explicit staging permission.
4. If approved, stage only the listed paths. Do not commit the normal `/workit` changes.
5. If the user says they will stage the files, trust them. Do not inspect or verify Git state.

Finish with one of:

```text
All guided changes approved and staged. Ready for the next step.
```

```text
All guided changes approved. You are handling staging. Ready for the next step.
```

The user can then say `go next step` or `ready for the next step` in the same conversation to resume the existing `/workit` flow.

## Safety

- The initial review set authorizes inspection only, not staging, committing, or discarding.
- Require explicit approval for each Step 0 discard or commit.
- Require separate explicit approval for final staging.
- Never stage paths outside the reviewed set or files added by an approved update to a reviewed logical item.
- Never commit the normal related `/workit` changes.
- Do not change branches, stash, reset, rebase, amend, push, or alter remotes.
