# Autofix Work Cycle participant

Follow these instructions only when the complete user message is exactly `AutoFixCycle <id>` with a numeric ID.

## Load authoritative context

1. Extract the Work Cycle ID from the message.
2. Run:

   ```text
   /Volumes/dev/bin/skills/autofix show-work-cycle <id>
   ```

3. Treat the returned JSON as authoritative. Do not query Autofix SQLite directly.
4. When the returned `feature_path` and `feature_text` are non-null, use that returned Feature text as shared goal, scope, and constraint context; let Task-specific inputs and requirements win conflicts, and do not treat the Feature inventory as requirements. Do not persist or rediscover the Feature text.
5. When those fields are null, do not perform a Feature lookup.
6. Read the complete `task.md` and `steps.md` when present under the returned `task_path`; apply them after any returned Feature context and keep Reported Issues as the correction inputs.
7. Keep the Pi session and pane in their existing working directory. For every file operation and command, target the returned `project_path` explicitly with absolute paths, `git -C`, or a per-command `cd`. Never rely on or change Pi's starting cwd.
8. Follow the section matching the returned `role` and `action`. If no section matches, write a failed result describing the mismatch and stop.

## Worker implementation

For role `worker` and action `implementation`:

1. Work only in the returned `project_path` checkout.
2. Inspect the current code and implement every Reported Issue in `inputs` as one coherent change.
3. Do not implement unrelated work.
4. Run focused checks when useful.
5. Do not stage or commit changes.
6. Do not write Autofix state.
7. Write a completed result with exactly the common fields below.

## Worker review

For role `worker` and action `review`:

1. Work only in the returned `project_path` checkout.
2. Review current `HEAD` in the authoritative checkout against every Reported Issue in `inputs`.
3. Inspect that commit's diff and relevant surrounding code.
4. Report only:
   - an input that the commit did not implement fully or correctly
   - a concrete bug or regression introduced by the commit
   - a concrete security problem, data-loss risk, or meaningful performance problem introduced by the commit
5. Do not report pre-existing or unrelated problems, style preferences, nits, speculative improvements, or missing tests without a concrete defect.
6. Do not edit, stage, or commit anything.
7. Do not run linters, specs, tests, or other checks.
8. Do not write Autofix state.
9. Write a completed result with the common fields plus a `reported_issues` array. Use one self-contained actionable Reported Issue body per element. Use an empty array when the review reports no issues.
10. Add no verdict, severity, summary, file-list, issue-ID, or commit-SHA fields.

## Reviewer review

For role `reviewer` and action `review`:

1. Work only in the returned `project_path` checkout.
2. Review current `HEAD` in the authoritative checkout against every Reported Issue in `inputs`.
3. Inspect that commit's diff, relevant surrounding code, and affected flows. Look for concrete regressions outside the directly changed behavior instead of reviewing the diff in isolation.
4. Reach your own conclusions from the implementation and inputs. Do not seek or infer another participant's review result.
5. Report only:
   - an input that the commit did not implement fully or correctly
   - a concrete bug or regression introduced by the commit
   - a concrete security problem, data-loss risk, or meaningful performance problem introduced by the commit
6. Do not report pre-existing or unrelated problems, style preferences, nits, speculative improvements, or missing tests without a concrete defect.
7. Do not edit, stage, or commit anything.
8. Do not run linters, specs, tests, or other checks.
9. Do not write Autofix state.
10. Write a completed result with the common fields plus a `reported_issues` array. Use one self-contained actionable Reported Issue body per element. Use an empty array when the review reports no issues.
11. Add no verdict, severity, summary, file-list, issue-ID, or commit-SHA fields.

## Report

Write valid JSON to `/tmp/autofix-work-cycle-<id>.json` only after the action finishes.

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

Use the actual numeric Work Cycle ID. Copy the returned `work_cycle_id`, `role`, and `action`. Copy `PI_PROVIDER`, `PI_MODEL`, and `PI_REASONING_LEVEL` when present; otherwise use JSON `null`. Do not infer missing provenance.

A completed review result also contains:

```json
{
  "reported_issues": []
}
```

If the action cannot complete, write the common fields with status `failed` and add a concise sanitized `error`. Do not include credentials or raw provider data.

After writing the result, stop. Manager owns result import, Autofix database writes, staging, and commits.
