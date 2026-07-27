# Final gates — final checks, super-review, base management, manager loop

Read this file when all planned steps are accepted and the run enters its final phases, or when a base rebase is needed.

## Final checks

Skip orchestrator-enforced checks between intermediate steps/fixes. Pi may run targeted checks and report them, but `/autowork` does not block intermediate commits on tests.

After all planned steps pass Claude review, run configured final checks. For Ruby projects with a `Gemfile`, default to:

```sh
bundle exec rubocop
bundle exec rspec
```

For non-Ruby or unconfigured repos, record final checks as skipped with a clear reason.

Final checks run through a non-login shell (`bash -c`) so the manager pane environment, including asdf shims in `PATH`, is preserved. Do not use `bash -lc` here; on macOS login-shell startup can reset `PATH` to system Ruby and make `bundle` resolve to `/usr/bin/bundle`.

If final checks fail:

1. write `final_checks.md`
2. send the failure output to Pi
3. Pi fixes without committing, or reports that no repo fix is needed
4. if Pi changed repo files, `/autowork` commits `Final checks fix M`
5. if Pi made no repo changes, `/autowork` reruns final checks without creating an empty commit
6. when checks pass, send any final-check fix commits to Claude for review
7. Claude reviews final-check fix commits without running RSpec, RuboCop, linters, formatters, or any other test/check command; it reads `final_checks.md` and inspects the fix commits
8. if Claude finds issues, send them to Pi as another final-check fix iteration
9. repeat until checks pass and Claude accepts, or until `max_final_check_fix_iterations` is hit

After final checks pass and any final-check fix commits are accepted, run the final super-review gate. The gate runs Claude's whole-branch review and resolves all Claude findings first, including scoped review of super-review fixes. Only then does it run the Pi-worker final review. Then stop at `ready_for_manager_final_review` so pi-manager can perform a manager-context production-readiness review using the original conversation, task creation, grilling, scope, and other manager-only context.

## Final super-review gate

After final checks pass, `/autowork` runs one final whole-branch `/claude-super-review` through `claude-worker`.

Base branch/ref rules:

- Normal tasks default to `main`/`master` as the review base.
- If the task branch is stacked on another feature branch, the user passes the full parent branch/ref to `/autowork`; do not infer it from a numeric task/story ID.
- Store the initial branch snapshot in `<task_folder>/autowork-log/config.yml` as `branch_name` and `starting_head_commit`.
- Store the initial resolved base in `config.yml` as `original_review_base_ref` and `original_review_base_commit`.
- Store the active/current review base separately as `review_base_ref`, `review_base_ref_is_explicit`, and `review_base_commit`; run the final review against `review_base_ref...HEAD`.
- `original_review_base_*` is audit/debug context and must not change after run initialization. `review_base_*` may change after an explicit rebase/base update.
- For explicit stacked bases, `/autowork` must detect when the base ref resolves to a different commit than `review_base_commit`. If it changed, pause before starting the next step/final phase and ask for explicit rebase/base-change instructions. Do not rebase automatically.
- After an intentional rebase or base change, update the recorded review base explicitly:
  ```text
  autowork update-base <task_folder> <new-base-ref>
  ```
  Use this when the parent branch advanced, or when the parent task merged and this task should now review against `main`/`master`.
- The super-review report must state the exact diff base used.

The final super-review wait uses `super_review_status_timeout_minutes: 20`, separate from normal `worker_status_timeout_minutes`.

If super-review finds actionable issues, `/autowork` sends them to `pi-worker` for `/claude-super-fix`-style adjudication and fixes. Pi may accept, disagree, mark already-fixed/out-of-scope/follow-up, or request user input. `/autowork` commits accepted code changes as `Super-review fix N`, reruns final checks, and sends those fix commits to Claude for a normal scoped review. It does not rerun full super-review by default.

After Claude's whole-branch super-review findings and any super-review fix commits have been accepted by Claude's scoped review, `/autowork` sends `pi-worker` a review-only prompt containing this exact goal: `review all the changes and try to find issues, gaps, and improvement opportunities. But ignore very minor issues`. Pi reviews the entire `review_base_ref...HEAD` diff without editing files, writes `autowork-log/pi-final-review.md`, and reports actionable `BLOCKER`/`MINOR` findings in `step0_pi_final_reviewN_status.json`. Pi's final-review findings are recorded for the manager gate and are not combined with Claude's findings or fed back into the Claude super-fix loop.

Final super-review report-only advisories, later-story recommendations, deploy notes, and smoke-test notes should be emitted as status JSON `followups` so `final_summary.md` does not contradict a "merge with follow-ups" report.

## Manual base rebase command

`/autowork rebase-base` is an explicit manual helper for stacked branches whose recorded autowork base advanced. It belongs in this skill because `/autowork` owns `review_base_ref` and `review_base_commit`, but normal orchestration must never auto-rebase.

Invocation:

```text
/autowork rebase-base
/autowork rebase-base <base-ref>
/autowork rebase-base <base-ref> --task <task_id>
```

Examples:

- Current base ref stays the same, but the ref advanced: `/autowork rebase-base`
- Parent branch merged and the task should now be based on `master`: `/autowork rebase-base master`
- The branch has no task-ID segment, so identify the task explicitly: `/autowork rebase-base main --task 0001`
- Task should move from one stacked parent to another: `/autowork rebase-base origin/example-parent-branch`

Rules:

1. Infer the task from the current repo/branch using normal task-resolution rules. If the branch has no inferable task-ID segment, require the explicit `--task <task_id>` fallback.
2. Load `<task_folder>/autowork-log/config.yml`.
3. Require `repo_dir`, `review_base_ref`, and `review_base_commit`; preserve `original_review_base_ref` and `original_review_base_commit` unchanged.
4. Require the repo worktree to be clean.
5. Require the current branch to equal stored `branch_name` when present.
6. Refuse to run while `<task_folder>/autowork-log/run.lock` exists.
7. Fetch origin.
8. If positional `<base-ref>` is passed, use that as the target base; otherwise use current `review_base_ref`.
9. Resolve the target base ref; after fetching, `master` means `origin/master` when it exists, and `main` means `origin/main` when it exists. Preserve full refs like `origin/example-parent-branch` exactly. Do not use branch upstream (`@{u}`).
10. Verify recorded `review_base_commit` is an ancestor of the current branch. If it is not, stop and ask for user direction.
11. Rebase the current branch from the recorded old base onto the target base ref:
    ```bash
    git -C <repo_dir> rebase --onto <target-base-ref> <review_base_commit>
    ```
12. If conflicts occur, resolve them when the correct resolution is clear. For each resolved conflict, write a report to `<task_folder>/autowork-log/rebase_conflicts.md` with: file, what conflicted, kept side or combined resolution, reason, checks run. If the correct resolution is not clear, leave the rebase paused, write the unresolved conflict report, and ask the user.
13. After a successful rebase, update active base metadata only (`review_base_ref`, `review_base_commit`); keep `original_review_base_ref` and `original_review_base_commit` unchanged.
14. Do not push.
15. Do not resume `/autowork` automatically; ask the user before continuing orchestration.

## Manager risk manifest

At the final manager gate, pi-manager reads the passive project registry:

```text
/Volumes/dev/_tasks/<project>/review-risk-registry.json
```

After forming the current view of the final diff, write this compact manifest:

```text
<task_folder>/autowork-log/review-risk-manifest.json
```

Required shape:

```json
{
  "summary": "...",
  "coverage_gaps": [],
  "registry_updates": []
}
```

`coverage_gaps` is required and must be an array. It must be empty before `manager-review-pass`. For every active registry risk that the current diff and reviews confirm, include an update for that existing risk ID in `registry_updates`, even when no new risk is being added. Existing-ID updates record the task/round recurrence and recompute the risk weight. Do not treat `registry_updates` as new entries only. Add only generalized, confirmed lessons; do not update a risk merely because it was considered. Omit unmatched or unconfirmed risks and explain important exclusions in `manager_review.md`. Do not copy code or raw review prose. The registry is passive data. Pi-manager reads and updates it; workers do not.

## Manager-context finding loop

The manager gate is the only phase that can use manager-only conversation context. It must still use the orchestrator for any code-changing response.

If manager review finds actionable issues:

1. Write all findings in one pass to the exact `manager_reviews/manager_reviewN_findings.json` path printed by `/autowork` and listed in `manager_review.md`.
2. Use this shape. Manager findings must use the existing autowork actionable severity vocabulary: `BLOCKER` or `MINOR`. Each gate also preserves a per-iteration human-readable copy at `manager_reviews/manager_reviewN.md`; `manager_review.md` is the current-gate copy.
   ```json
   {
     "summary": "Why manager review did not pass",
     "findings": [
       {
         "id": "MR1",
         "severity": "BLOCKER",
         "title": "Short title",
         "body": "What is wrong and why it matters",
         "recommendation": "Concrete required fix"
       }
     ],
     "followups": []
   }
   ```
3. Invoke `autowork manager-review-fix <task_folder>` immediately. The original `/autowork` invocation grants this manager loop permission to stage and commit according to the protocol; do not ask the user to route each finding.
4. The helper validates the findings and clean branch, sends a Pi fix prompt through `Tmux#send_prompt`, waits for status JSON, commits `Manager review fix N`, reruns configured full final checks, and sends the commit to Claude for scoped review.
5. If Claude finds issues in the manager fix, `/autowork` sends all of them back to Pi in the next manager-fix iteration. Pi may request user input but may not silently defer or dispute a manager-context requirement.
6. When Claude accepts, `/autowork` returns to a fresh `ready_for_manager_final_review` gate. Pi-manager reviews the final result again using manager-only context.
7. Only `autowork manager-review-pass <task_folder>` marks the run complete.

Do not manually call `tmux send-keys`, stage, commit, or construct ad hoc manager-fix status files. Normal resume rules apply if a worker timeout interrupts the manager-fix loop.

Finish only when final checks pass, final-check fix commits are accepted, all Claude super-review findings and fix reviews are resolved, the Pi final review has completed, every manager-fix commit has passed scoped Claude review, and pi-manager records that the result is production-ready if the user does not perform another review. Successful completion writes `final_summary.md`.

## Final output

At the manager review gate, write:

```text
autowork-log/final_summary.md
autowork-log/manager_review.md
```

Include:

- task path
- repo path
- steps completed
- commits created
- reviews and outcomes
- debates and final decisions
- final checks and results
- final super-review, Pi final-review, and super-review fix outcomes
- manager-context production-readiness review result
- any unresolved caveats

Then stop and tell pi-manager where to review. If findings exist, write the printed structured findings file and route it with `autowork manager-review-fix <task_folder>`. After the automated fix/check/Claude-review loop returns to a fresh manager gate, review again. If the manager-context review passes, record completion with `autowork manager-review-pass <task_folder>`.

Final output after that pass:

```text
/autowork complete. Production-readiness manager review passed.
- summary: <task_folder>/autowork-log/final_summary.md
- manager review: <task_folder>/autowork-log/manager_review.md
```

No push, no PR creation, no squash.
