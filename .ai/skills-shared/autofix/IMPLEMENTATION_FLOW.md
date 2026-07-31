# Autofix implementation flow

## Purpose

Build Autofix through small vertical increments. At the end of every task:

- `/skill:autofix` is runnable.
- Backward compatibility with earlier increments is not assumed. During each task's grilling session or when planning implementation, explicitly decide which existing inputs and behaviors are retained, replaced, or removed.
- The task adds one useful feature or improvement.
- RSpec and RuboCop pass for the implemented Ruby behavior.
- The new external behavior is manually QAed through Pi against a real GitHub pull request or real local clipboard review, as the task requires.

Do not test `gh`, `git`, or `tmux` behavior through complex stubs. Real-PR QA is the integration test for GitHub boundaries. Real clipboard extraction must be QAed through the manager model in Pi; deterministic Ruby persistence and validation receive automated specs.

Before every manual QA round, follow `qa.md`: show the applicable prerequisites, wait for the operator to confirm readiness, and trust that confirmation instead of inspecting setup state. Continue to verify actual outcomes after QA starts.

Before implementing each task:

1. Run a grilling session limited to that task.
2. Store the task-specific decisions in its task folder.
3. Reference `DEVELOPMENT_PRINCIPLES.md` from the task.
4. Split the task again if grilling reveals more than one substantial integration boundary.

## Phase 1: Read and retain reported issues

### Task 1: Fetch one comment

- Accept one inline GitHub comment URL.
- Fetch and print that comment.
- Create only the minimum runnable Autofix skill and Ruby CLI needed for this behavior.

Real QA: run Autofix against one real inline-comment URL and verify the displayed comment.

### Task 2: Discover the current PR

- Replace the supplied comment URL interface with current-branch pull request discovery.
- Remove the single-comment URL behavior from Task 1.
- Retrieve the discovered pull request's inline review comments.
- Display only the first comment returned by GitHub, then stop.

Real QA: run Autofix without arguments inside a checkout whose branch has a real pull request and verify that only the first returned inline comment is displayed.

### Task 3: Persist GitHub reported issues

- Add SQLite, Sequel, migrations, and one generic `reported_issues` table.
- Give every table an integer primary ID and creation timestamp while enforcing issue domain identity separately.
- Fetch every inline-comment page and store new GitHub issues with their raw comment bodies.
- Refresh unresolved raw bodies from the fresh GitHub response.
- Select unresolved stored GitHub issues from the fresh current-PR response by database ID.

Real QA: run Autofix against a real pull request and verify fetch, persistence, selection, and display.

### Task 4: Import local reported issues

- Add `/skill:autofix --local` while retaining no-argument GitHub behavior.
- Let agent-manager extract concrete concerns from `pbpaste` into concise, self-contained issue bodies.
- Pass bodies through a temporary JSON array and delete the file after import.
- Persist each issue with source `local`, no source ID, and the current project path.
- Select unresolved local issues by database ID.

Real QA: import a real multi-issue review through Pi and verify extracted and retained issues.

## Phase 2: Decide and implement one batch

### Task 5: Record decisions

- Display every issue with its generated database ID.
- Present one unresolved issue at a time.
- Record `approved` or `skipped` on the exact displayed issue.
- Show the stored decision and then the next issue.

Real QA: approve and skip real GitHub and local issues through natural Pi replies.

### Task 6: Run one implementation Work Cycle

- If the source contains no new issues, create no Review or Work Cycle, perform no Git mutation, and report `No issues found.`.
- Otherwise create one Review for the active set of new GitHub or local feedback and assign its next project-scoped number.
- Refactor the GitHub skill flow so Manager directly runs `gh`, uses `app/prompts/normalize_github_issue.md` with comment path/line/diff and current code context, and invokes Ruby to import only normalized data.
- Normalize every concrete concern even when its line is outdated, its code was deleted, or it appears resolved. Preserve evidence and defer validity to the operator's decision.
- Manager also runs external Git commands to resolve the current branch name and selected base ref/commit SHA for both GitHub and local Reviews. Review JSON contains `branch_name`, `base_ref`, `base_commit_sha`, and `issues`; Ruby resolves the canonical project path and stores the supplied metadata.
- Delete normalized temporary files after import succeeds or fails. Never store the raw GitHub response, and do not refetch GitHub after decisions.
- Persist each GitHub or local import atomically: issue changes, Review creation, and all issue relationships commit in one SQLite transaction.
- For GitHub, use the PR base branch and resolved commit unless the operator supplies an explicit `--base <ref>` override.
- For local feedback, use explicit `--base <ref>` when supplied, otherwise `origin/main`, then `origin/master`.
- Associate every active issue, including skipped issues, with that Review.
- Treat its approved issues as one implementation batch after the unresolved queue becomes empty.
- Immediately before every Work Cycle, require `git status --porcelain` to be empty. A dirty tree fails before participant action or delivery and preserves the Review for resume.
- After the first Work Cycle's clean-tree check passes, capture current `HEAD` as the Review's starting commit. Leave it null during `manager_issue_selection` and for an all-skipped Review.
- If every issue is skipped, complete the numbered Review without requiring a clean tree or creating a Work Cycle, commit, or push.
- Add durable Reviews, Work Cycles, Review issues, Work Cycle inputs, and Work Cycle findings.
- Persist the Review state as `manager_issue_selection`, `worker_implementation`, `worker_review`, `reviewer_review`, `manager_review`, `manager_finalizing`, or `completed`.
- On every invocation, continue an incomplete Review for the current project and branch from its stored state instead of repeating source or base arguments.
- Add shared participant instructions that every agent loads by default. The exact message `AutoFixCycle <id>` makes the participant run the read-only `autofix show-work-cycle <id>` command and follow the returned role, action, project, commit, inputs, and findings.
- Allowlist that exact read command for both Pi and Claude; do not allow arbitrary SQLite commands.
- Manager sends only `AutoFixCycle <id>` to `agent-worker`, then blocks in `autofix wait-work-cycle <id>` while Ruby polls `/tmp/autofix-work-cycle-<id>.json` once per second with no timeout.
- If waiting is interrupted, resume waits for the same Work Cycle without redispatching it.
- Worker modifies the correct checkout and writes a `completed` or `failed` result without writing the database.
- A failed result includes an error; Manager exposes it, leaves the Work Cycle incomplete, retains the file, and does not retry or commit.
- For a completed implementation result, Ruby stages all changes, creates local `Work cycle <id>`, reads and stores its full SHA with the result and actual provenance, advances the Review, and deletes the result file. Do not push interim commits.
- Completed review Work Cycles store their result and advance state without creating a commit.

Real QA: classify a real multi-issue source, send one approved batch to `agent-worker`, receive completion, and create the implementation commit.

### Task 7: Run one Worker review Work Cycle

- Create a Worker review Work Cycle for the implementation commit and its reported issues.
- Send only `AutoFixCycle <id>` to `agent-worker`; shared participant instructions make Worker load its review context through `autofix show-work-cycle <id>`, review without modifying, and write the expected result file.
- Manager imports and deletes the file, completes the Work Cycle, displays the review result, and stops.

Real QA: have `agent-worker` review one real Autofix implementation commit.

### Task 8: Run one independent review Work Cycle

- Create a Reviewer review Work Cycle for the same implementation commit and reported issues.
- Send only `AutoFixCycle <id>` to `agent-reviewer`; shared participant instructions make Reviewer load its review context through `autofix show-work-cycle <id>`, review independently without modification, and write the expected result file.
- Manager imports and deletes the file, completes the Work Cycle, displays the review result, and stops.

Real QA: have `agent-reviewer` independently review one real Autofix implementation commit.

## Phase 3: Turn findings into corrections

### Task 9: Capture and settle review findings

- Convert actionable findings from Worker or Reviewer review Work Cycles into reported issues sourced from those Work Cycles.
- Link each finding to its producing review Work Cycle while preserving access to the reviewed commit and originating issue batch.
- Present findings to Manager for `approved` or `skipped` decisions.
- Stop without implementing corrections.

Real QA: retain and settle at least one real review finding.

### Task 10: Run one correction Work Cycle

- Send approved review findings to `agent-worker` as one correction implementation Work Cycle.
- Preserve the Work Cycle chain and original issue context.
- Let Manager create one local `Work cycle <id>` commit for the completed corrections and retain its SHA. Do not push interim commits.
- Stop before another review.

Real QA: implement and commit one real approved review correction batch.

### Task 11: Repeat review and correction Work Cycles

- Run Worker and independent Reviewer review Work Cycles for each correction commit.
- Convert new findings into reported issues and let Manager settle them.
- Continue with another correction implementation Work Cycle when approved findings remain.
- Escalate ambiguity to the operator instead of adding automatic debate machinery.

Real QA: complete at least one correction and second review cycle.

## Phase 4: Make Autofix durable and final

### Task 12: Rebase an active Review

- Add explicit `/skill:autofix --rebase-base [<base-ref>]` using frozen original and mutable active base metadata.
- Rebase the stored Review branch onto the current or supplied base without switching branches, pushing, or automatically continuing orchestration.
- Update active base metadata, the rebased Review starting commit, and rebased Work Cycle commit SHAs while preserving original base metadata.

Real QA: rebase one active Review onto an advanced or different base and then continue it through normal Autofix invocation.

### Task 13: Support repeated external Reviews

- Remember addressed and skipped GitHub, local, and Work Cycle reported issues.
- Select only new or explicitly reopened external feedback during later GitHub fetches or local imports.
- Start the next project-scoped Review for that later feedback without changing earlier Reviews.

Real QA: process two external Reviews without reselecting terminal issues.

### Task 14: Run Manager review and finalize

- Record the final Manager review as a Manager review Work Cycle after Worker and Reviewer Work Cycles pass.
- Convert Manager findings into reported issues and route approved findings through the same correction loop.
- After Manager review passes, enter `manager_finalizing` and run configured final checks.
- Stop and report failing checks before squash or push. Interrupted checks may run again on resume.
- After checks pass, squash the Review's implementation commits into one `Review N` commit and push it.
- Complete the Review only after that push.

Real QA: complete one real run with passing Manager review and final checks, and separately verify one failing-check stop before squash or push.

### Task 15: Assess Addressit replacement

- Compare actual Autofix usage with Addressit for GitHub and local sources.
- Add only missing behavior proven necessary by real usage.
- Decide whether Autofix can become the default.

Real QA: use Autofix for normal real GitHub and local Reviews without Addressit, or record the concrete blocker.
