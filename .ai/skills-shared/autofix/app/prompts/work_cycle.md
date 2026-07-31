# Autofix Work Cycle participant

Follow these instructions only when the complete user message is exactly `AutoFixCycle <id>` with a numeric ID.

## Load authoritative context

1. Extract the Work Cycle ID from the message.
2. Run:

   ```text
   /Volumes/dev/bin/skills/autofix show-work-cycle <id>
   ```

3. Treat the returned JSON as authoritative. Do not query Autofix SQLite directly.
4. Require role `worker` and action `implementation`. If either differs, write a failed result describing the mismatch and stop.

## Implement

1. Work only in the returned `project_path` checkout.
2. Inspect the current code and implement every Reported Issue in `inputs` as one coherent change.
3. Do not implement unrelated work or items in `findings`.
4. Run focused checks when useful.
5. Do not stage or commit changes.
6. Do not write Autofix state.

## Report

Write valid JSON to `/tmp/autofix-work-cycle-<id>.json` only after implementation and checks finish.

For success, write exactly these fields:

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

Use the actual numeric Work Cycle ID. Copy the returned `work_cycle_id`, `role`, and `action` in every result. Copy `PI_PROVIDER`, `PI_MODEL`, and `PI_REASONING_LEVEL` when present; otherwise use JSON `null`. Do not infer missing provenance.

If implementation cannot complete, write the same fields with status `failed` and add a concise sanitized `error`. Do not include credentials, raw provider data, Issue IDs, project paths, changed-file lists, summaries, or commit SHAs.

After writing the result, stop. Manager owns result import, Autofix database writes, staging, and commits.
