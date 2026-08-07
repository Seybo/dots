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
5. Follow the section matching the returned `role` and `action`. If no section matches, write a failed result describing the mismatch and stop.

## Worker implementation

For role `worker` and action `implementation`:

1. Read the complete `task.md` and `steps.md` under the returned `task_path`.
2. Locate the returned `step_number` section from its exact `## Step N` heading up to before the next canonical `## Step <number>` heading.
3. When `inputs` is empty, use the complete Task and plan as context but implement only the selected step section.
4. When `inputs` is not empty, treat the Work Cycle as a correction. Inspect the current implementation and implement every approved Reported Issue in `inputs` as one coherent correction to the selected step. Do not implement unrelated changes.
5. Inspect relevant project code and run focused checks when useful.
6. Do not implement later steps.
7. Do not stage, commit, push, switch branches, or write workflow state.
8. Write a completed result with exactly the common fields below.

## Reviewer review

For role `reviewer` and action `review`:

1. Read the complete `task.md` and `steps.md` under the returned `task_path`.
2. Locate the returned `step_number` section from its exact `## Step N` heading up to before the next canonical `## Step <number>` heading.
3. Require a positive `step_commit_count`. Review the complete cumulative step diff using:

   ```text
   git -C <project_path> diff HEAD~<step_commit_count>..HEAD
   ```

4. Verify the selected step against the complete Task and plan. When `inputs` is not empty, verify every approved correction input was resolved.
5. Inspect relevant surrounding code and affected flows rather than reviewing the diff in isolation. Reach your own conclusions; do not seek or infer another participant's review result.
6. Report only:
   - a Task requirement the implementation did not satisfy fully or correctly
   - a concrete bug or regression introduced by the step
   - a concrete security problem, data-loss risk, or meaningful performance problem introduced by the step
7. Do not report pre-existing or unrelated problems, style preferences, nits, speculative improvements, or missing tests without a concrete defect.
8. Do not edit, stage, commit, push, switch branches, run linters/specs/tests/checks, or write workflow state.
9. Write a completed result with the common fields plus a `reported_issues` array. Use one self-contained independently actionable Reported Issue body per element, in review order. Use an empty array when the review reports no issues.
10. Add no verdict, severity, summary, file list, issue ID, commit SHA, or other fields.

## Report

Write valid JSON to `/tmp/autoimplement-work-cycle-<id>.json` only after the action finishes.

Every completed result contains these common fields:

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

Use the actual numeric Work Cycle ID. Copy `work_cycle_id`, `role`, and `action` from the returned context. Copy `PI_PROVIDER`, `PI_MODEL`, and `PI_REASONING_LEVEL` when present; otherwise use JSON `null`. Do not infer missing provenance.

A completed Reviewer result also contains:

```json
{
  "reported_issues": []
}
```

If the action cannot complete, write the common fields with status `failed` and add a concise sanitized `error`. Do not include credentials or raw provider data.

After writing the result, stop. Manager owns result import, Autoimplement database writes, staging, commits, issue decisions, and progression.
