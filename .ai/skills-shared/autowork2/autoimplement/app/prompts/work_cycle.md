# Autoimplement Work Cycle participant

Follow these instructions only when the complete user message is exactly `AutoImplementCycle <id>` with a numeric ID.

## Load authoritative context

1. Extract the Work Cycle ID from the message.
2. Run:

   ```text
   /Volumes/dev/bin/skills/autoimplement show-work-cycle <id>
   ```

3. Treat the returned JSON as authoritative. Do not query or write Autoimplement SQLite directly.
4. Keep the Pi session and pane in their existing working directory. Target the returned `project_path` explicitly with absolute paths, `git -C`, or a per-command `cd`. Do not select or switch the project or branch.
5. Require role `worker` and action `implementation`. If they do not match, write a failed result describing the mismatch and stop.

## Implement the selected step

1. Read the complete `task.md` and `steps.md` under the returned `task_path`.
2. Locate the returned `step_number` section from its exact `## Step N` heading up to before the next canonical `## Step <number>` heading.
3. Use the complete Task and plan as context, but implement only the selected step.
4. Inspect relevant project code and run focused checks when useful.
5. Do not implement later steps.
6. Do not stage, commit, push, switch branches, or write workflow state.

## Report

Write valid JSON to `/tmp/autoimplement-work-cycle-<id>.json` only after the action finishes:

```json
{
  "work_cycle_id": 12,
  "role": "worker",
  "action": "implementation",
  "status": "completed",
  "provider": null,
  "model": null,
  "reasoning_level": null
}
```

Use the actual numeric Work Cycle ID. Copy `work_cycle_id`, `role`, and `action` from the returned context. Copy `PI_PROVIDER`, `PI_MODEL`, and `PI_REASONING_LEVEL` when present; otherwise use JSON `null`. Do not infer missing provenance or add other fields.

If implementation cannot complete, write the same fields with status `failed` and add a concise sanitized `error`. Do not include credentials or raw provider data.

After writing the result, stop. Manager owns result import, Autoimplement database writes, staging, and commits.
