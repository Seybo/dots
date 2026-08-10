# Autoimplement Work Cycle execution

Follow these instructions only when the complete user message is exactly `AutoImplementCycle <id>` with a numeric ID, or when the Autoimplement skill routes a persisted `manager`/`review` Work Cycle inline in the current Manager conversation.

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
2. When returned `scope` is `step_implementation`:
   - require a positive `step_number`
   - locate that section from its exact `## Step N` heading up to before the next canonical `## Step <number>` heading
   - when `inputs` is empty, use the complete Task and plan as context but implement only the selected step section
   - when `inputs` is not empty, implement every approved Reported Issue as one coherent correction to the selected step
   - do not implement later steps
3. When returned `scope` is `whole_task_correction`:
   - require `step_number` to be null and `inputs` to be non-empty
   - inspect the complete Task implementation and implement every approved Reported Issue in `inputs` as one coherent whole-task correction
   - do not locate or limit the correction to one authored step
4. For any other scope, write a failed result describing the mismatch and stop.
5. Do not implement unrelated changes.
6. Inspect relevant project code and run focused checks when useful.
7. Do not stage, commit, push, switch branches, or write workflow state.
8. Write a completed result with exactly the common fields below.

## Final Worker self-review

For role `worker` and action `review`:

1. Read the complete `task.md` and `steps.md` under the returned `task_path`.
2. Require returned `scope` is `final_worker_review`, `step_number` and `step_commit_count` are null, and `inputs` is empty.
3. Review the complete Task diff using:

   ```text
   git -C <project_path> diff <starting_commit_sha>..HEAD
   ```

4. Inspect relevant surrounding code and affected flows rather than reviewing the diff in isolation.
5. Report only:
   - an unmet Task requirement across the complete implementation
   - a concrete cross-step bug or regression
   - a concrete security problem or data-loss risk
   - a meaningful performance defect
6. Do not report style, nits, speculative improvements, or missing tests without a concrete defect.
7. Do not edit, stage, commit, push, switch branches, run linters/specs/tests/checks, or write workflow state.
8. Write a completed result with the common fields plus a `reported_issues` array. Use one self-contained actionable Reported Issue body per element, in review order. Use an empty array when the review reports no issues.
9. Add no verdict, severity, summary, file list, issue ID, commit SHA, or other fields.

## Reviewer review

For role `reviewer` and action `review`:

1. Read the complete `task.md` and `steps.md` under the returned `task_path`.
2. When returned `scope` is `super_review`:
   - require `step_number` and `step_commit_count` to be null and `inputs` to be empty
   - treat this persisted Work Cycle as explicit authorization to run the shared super-review workflow
   - run it in Autoimplement non-interactive mode with the returned `super_review_agent` over exactly `<starting_commit_sha>..HEAD`
   - provide the complete Task and plan as review intent; do not infer main or master as the base
   - preserve the shared candidate generation, adversarial adjudication, evidence validation, and synthesis
   - convert every concern surfaced in the final synthesis into one self-contained `reported_issues` body in report order, including actionable, contested, intent-verification, and manual-verification concerns
   - include the trigger, mechanism, evidence or evidence gap, and concrete recommendation supplied by the synthesis
   - do not include rejected raw candidates, clean confirmations, report statistics, or raw reviewer/adjudication output
   - remove the generated human report before publishing the Work Cycle result; do not post comments
3. When returned `scope` is `step_review`:
   - require a positive `step_number` and `step_commit_count`
   - locate that section from its exact `## Step N` heading up to before the next canonical `## Step <number>` heading
   - review the complete cumulative step diff using:

     ```text
     git -C <project_path> diff HEAD~<step_commit_count>..HEAD
     ```

   - verify the selected step against the complete Task and plan
4. When returned `scope` is `whole_task_correction_review`:
   - require `step_number` to be null, `step_commit_count` to equal `1`, and `inputs` to be non-empty
   - review exactly the correction commit using:

     ```text
     git -C <project_path> diff HEAD~1..HEAD
     ```

   - verify the whole-task correction against the complete Task and plan
   - before reporting a concern, compare it with `HEAD~1`; report it only when an approved input remains unresolved or the correction introduced it, and exclude every unrelated defect that already existed before the correction
5. For any other scope, write a failed result describing the mismatch and stop.
6. When `inputs` is not empty, verify every approved correction input was resolved.
7. Inspect relevant surrounding code and affected flows rather than reviewing the diff in isolation. Reach your own conclusions; do not seek or infer another participant's review result.
8. Report only:
   - a Task requirement the implementation did not satisfy fully or correctly
   - a concrete bug or regression introduced by the reviewed implementation or correction
   - a concrete security problem, data-loss risk, or meaningful performance problem introduced by the reviewed change
9. Do not report pre-existing or unrelated problems, style preferences, nits, speculative improvements, or missing tests without a concrete defect.
10. Do not edit, stage, commit, push, switch branches, run linters/specs/tests/checks, or write workflow state.
11. Write a completed result with the common fields plus a `reported_issues` array. Use one self-contained independently actionable Reported Issue body per element, in review order. Use an empty array when the review reports no issues.
12. Add no verdict, severity, summary, file list, issue ID, commit SHA, or other fields.

## Manager review

For role `manager` and action `review`:

1. Require returned `scope` is `manager_review`, `step_number` and `step_commit_count` are null, and `history` is the complete ordered Work Cycle history.
2. Run this review inline in the current Manager conversation. Do not contact a participant pane.
3. Read the complete `task.md` and `steps.md`; `task.md` and `steps.md` remain authoritative when prior conversation is absent.
4. Use the complete ordered `history`, including every input, produced issue, decision, and completion state. Also use live Manager conversation context when available, including task creation and grilling decisions. Do not persist that conversation.
5. Review the complete Task diff using:

   ```text
   git -C <project_path> diff <starting_commit_sha>..HEAD
   ```

6. Inspect the complete commit list, relevant surrounding code, and affected flows. Judge the implementation against every authored step as one whole Task.
7. Report only an unmet Task requirement, concrete bug or regression, concrete security or data-loss risk, or meaningful performance defect. Do not report style, nits, speculative improvements, or missing tests without a concrete defect.
8. Apply normal judgment to prior issues and decisions. Do not suppress a concern because history contains a similar concern.
9. Do not edit, stage, commit, push, switch branches, run linters/specs/tests/checks, or write workflow state.
10. Write a completed result with the common fields plus a `reported_issues` array. Use one self-contained independently actionable Manager concern per element, in review order. Use an empty array when the review reports no issues.
11. Add no verdict, severity, summary, file list, issue ID, commit SHA, transcript, or other fields.

## Report

After the action finishes, write the complete valid JSON payload to this temporary path:

```text
/tmp/autoimplement-work-cycle-<id>.json.tmp
```

Do not create the final result path until the temporary file is complete. Then publish the result with this same-directory atomic rename:

```text
mv /tmp/autoimplement-work-cycle-<id>.json.tmp /tmp/autoimplement-work-cycle-<id>.json
```

Outside a super-review's own temporary artifact and worktree lifecycle, the temporary and final result paths are the only files the Work Cycle executor may intentionally author outside the returned project path. Focused tools may manage their own ignored caches or temporary files; do not treat those as workflow state. Autoimplement imports only the final `.json` path.

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

A completed Worker, Reviewer, or Manager review result also contains:

```json
{
  "reported_issues": []
}
```

If the action cannot complete, use the same temporary-file and atomic-rename publication steps for the common fields with status `failed` and a concise sanitized `error`. Do not include credentials or raw provider data.

After atomically publishing the result, return control to Autoimplement orchestration. Manager owns result import, Autoimplement database writes, staging, commits, issue decisions, and progression.
