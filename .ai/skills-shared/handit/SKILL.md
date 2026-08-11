---
name: handit
description: >-
  Pass the current Pi development session to a Dropbox-synced mobile discussion
  bundle, or receive the resulting mobile discussion back into the original Pi
  session for read-only reconciliation. Command-only skill. In Pi, invoke via
  /skill:handit; /handit is also accepted where that alias is exposed.
allowed-tools:
  - "bash(ruby /Users/inseybo/.ai/skills-shared/handit/scripts/handit.rb *)"
disable-model-invocation: true
---

# Handit

This is a command-only Pi workflow. It transfers discussion context, not the repository or development environment.

## Invocation

```text
/skill:handit pass
/handit pass
/skill:handit pass --allow-sensitive
/handit pass --allow-sensitive
/skill:handit receive
/handit receive
```

Reject every other argument shape with:

```text
Usage: /handit pass [--allow-sensitive] | /handit receive
```

## Resolve the current draft or Task

Read and follow `../components/task-resolution.md` and `../components/projects.yml`.

Require exactly one existing canonical draft or numbered Task folder directly under:

```text
/Volumes/dev/_tasks/<project>/
```

Use an exact Task path already established by the active Grillme, Draftit, Taskit, Workit, Autoimplement, or Autofix conversation when one exists. Otherwise use the shared current-checkout, workspace, and `sc-<digits>` branch rules. Verify the resolved folder and its `task.md` on disk.

If those sources do not identify exactly one draft or Task, stop. Do not show a picker, choose the newest Task, scan unrelated task folders, or guess from general conversation text.

## Pass

1. Resolve the current draft or Task.
2. Produce a concise adaptive summary from the active session context. Include only material useful to continuing the current discussion, such as current progress, established repository facts, decisions and reasons, the current proposal, open questions, or items requiring repository verification. Omit irrelevant or empty sections. Do not treat the summary as a replacement for the native session JSONL.
3. Write only that adaptive summary to:

   ```text
   /tmp/handit-<project>-<task-folder>-summary.md
   ```

   The helper adds the stable Android instructions and removes this temporary file after use, including on failure.
4. Run:

   ```text
   ruby /Users/inseybo/.ai/skills-shared/handit/scripts/handit.rb pass <canonical-task-folder> <summary-file>
   ```

   For the exact `pass --allow-sensitive` invocation, append `--allow-sensitive`. Never add the override on your own.
5. The helper uses Pi's official `PI_SESSION_FILE` and `PI_SESSION_ID`, validates and snapshots the full native JSONL, runs dots-check, and atomically publishes the bundle. Do not copy or edit Pi session files yourself.
6. If dots-check blocks the pass, surface its redacted findings and the explicit override command. Do not redact, filter, partially publish, or bypass the result.
7. On normal success, return only the concise helper completion and export path. When an explicit sensitive override exports findings, preserve the helper's redacted findings before the completion. Do not add Dropbox synchronization reminders or other follow-up advice.

## Receive

1. Resolve the same draft or Task in the original Pi session.
2. Run:

   ```text
   ruby /Users/inseybo/.ai/skills-shared/handit/scripts/handit.rb receive <canonical-task-folder>
   ```

   The helper validates the bundle, original Pi session ID, and non-empty `TRANSIT.md`, then prints its path.
3. Read the complete `TRANSIT.md` with the read tool. Do not issue the read and cleanup calls in one parallel tool batch. Wait for the read result before continuing. If reading is truncated or fails, leave the cloud bundle intact and stop.
4. Treat the read result as mobile decisions and reasoning added while Pi and the repository were unavailable. It is now durable Pi session context, but it is not automatically a repository fact or workflow-state change.
5. Reconcile in read-only mode:
   - verify every `VERIFY ON MAC` item and any repository-dependent claim against current files and read-only Git state;
   - prefer the live repository and authoritative local workflow state when they conflict with mobile conclusions;
   - explain concrete conflicts or unresolved questions;
   - otherwise preserve settled mobile decisions without re-litigating them;
   - propose the exact document, workflow-state, or implementation continuation owned by the active local workflow.
6. Do not edit `task.md`, `steps.md`, code, Git state, or Autoimplement/Autofix data. Do not run checks or invoke another workflow. Wait for explicit user approval before the owning workflow makes changes.
7. After the complete transit content has been read and reconciliation is ready, run this as a separate tool call:

   ```text
   ruby /Users/inseybo/.ai/skills-shared/handit/scripts/handit.rb complete <canonical-task-folder>
   ```

8. Present the reconciliation and wait for approval. If cleanup fails, retain the reconciliation but report the cleanup failure.

## Boundaries

- `session.jsonl` is the authoritative historical context; `HANDOFF.md` is only an adaptive index.
- Android may explain, challenge, compare, or grill decisions, but it does not execute local commands or advance local workflow state.
- Handit never merges Pi and ChatGPT session formats.
- Handit never copies the repository to Dropbox.
