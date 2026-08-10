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

### Task 5: Assess issues and record decisions

- Present one unresolved issue at a time with its generated database ID.
- Before the operator decides, Manager inspects relevant current code and Review context without editing or running checks. Present the complete original issue body first in a Markdown quote block, then a one- or two-sentence `TLDR:` in a second quote block, then a Fix, Skip, or Unclear recommendation with a brief reason.
- A request for more code or Review context records no decision.
- Treat the assessment as advisory and regenerate it whenever the same undecided issue is shown. Persist no explanation, recommendation, question, or assessment state.
- For Unclear, name the missing fact, prefer one precise yes-or-no question when possible, and persist nothing while clarifying. A clarification answer is not an implicit decision.
- Treat `fix`, `approve`, and `approved` as `approved`; treat `skip`, `ignore`, `reject`, and `invalid` as `skipped`. Treat `yes` and `go` as accepting Manager's current recommendation: Fix becomes `approved`, Skip becomes `skipped`, and Unclear remains clarification without a decision.
- Record `approved` or `skipped` on the exact assessed issue only after the operator decides.
- Show the stored decision and then assess the next issue through the same source-neutral flow. GitHub, local, Worker, Reviewer, and Manager issues use identical presentation and decision behavior.

Real QA: assess, reveal details, clarify, approve, and skip imported and review-reported issues through natural Pi replies.

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
- After the first Work Cycle's clean-tree check passes, capture current `HEAD` as the Review's starting commit. Leave it null during `manager_issues_assessment` and for an all-skipped Review.
- If every issue is skipped, complete the numbered Review without requiring a clean tree or creating a Work Cycle, commit, or push.
- Add durable Reviews, Work Cycles, Review issues, Work Cycle inputs, and Work Cycle reported-issue relationships.
- Persist the Review state as `manager_issues_assessment`, `worker_implementation`, `reviewer_review`, `worker_review`, `manager_review`, `manager_finalizing`, or `completed`.
- On every invocation, continue an incomplete Review for the current project and branch from its stored state instead of repeating source or base arguments.
- Add shared participant instructions that every agent loads by default. The exact message `AutoFixCycle <id>` makes the participant run the read-only `autofix show-work-cycle <id>` command and follow the returned role, action, project, commit, inputs, and review-reported issues.
- Allowlist that exact read command for both Pi and Claude; do not allow arbitrary SQLite commands.
- Manager sends only `AutoFixCycle <id>` to `agent-worker`, then blocks in `autofix wait-work-cycle <id>` while Ruby polls `/tmp/autofix-work-cycle-<id>.json` once per second with no timeout.
- If waiting is interrupted, resume waits for the same Work Cycle without redispatching it.
- Worker modifies the correct checkout and writes a `completed` or `failed` result without writing the database.
- A failed result includes an error; Manager exposes it, leaves the Work Cycle incomplete, retains the file, and does not retry or commit.
- For a completed implementation result, Ruby stages all changes, creates local `Work cycle <id>`, stores completion and actual agent provenance without the interim commit SHA, advances the Review, and deletes the result file. Do not push interim commits.
- Completed review Work Cycles store completion, provenance, and any Reported Issues, then advance state without creating a commit.

Real QA: classify a real multi-issue source, send one approved batch to `agent-worker`, receive completion, and create the implementation commit.

### Task 7: Add one Worker review Work Cycle

- Add the deterministic Worker review Work Cycle, result transport, completion persistence, and participant behavior.
- Task 8 reorders this capability so Worker review no longer starts immediately after implementation.

Real QA: have `agent-worker` review one real Autofix implementation commit.

### Task 8: Run Reviewer before the one final Worker review

- After implementation is committed, create a Reviewer review Work Cycle for that commit and its reported issues before Worker review.
- Send only `AutoFixCycle <id>` to `agent-reviewer`; shared participant instructions make Reviewer load its review context through `autofix show-work-cycle <id>`, review independently without modification, and write the expected result file.
- Reviewer evaluates the exact commit in the context of relevant surrounding code and affected flows. It looks for incomplete fixes and concrete regressions introduced outside the directly changed behavior, not only defects visible in the diff in isolation.
- When Reviewer reports issues, retain and display them and do not start Worker review. Persistence and decisions continue in Task 9; later implementation continues in subsequent tasks.
- When Reviewer reports no issues, create the Review's one final Worker review Work Cycle. Worker reviews independently without receiving Reviewer result content.
- Worker review runs at most once per Review. Later implementations caused by Worker-reported issues return through Reviewer and never trigger another Worker review.
- Manager imports and deletes each result file and displays implementation, Reviewer, and Worker completion results in Work Cycle order.

Real QA: have `agent-reviewer` independently review one real Autofix implementation commit, then automatically run the one final Worker review only after Reviewer passes.

## Phase 3: Handle issues reported by reviews

### Task 9: Capture and settle review-reported issues

- Store each Reported Issue from a Worker or Reviewer review Work Cycle directly with source `worker` or `reviewer`, no source ID, and no extra issue metadata.
- Atomically complete the Work Cycle, store its provenance, create its Reported Issues, link them to the Review and producing Work Cycle, and move the Review to `manager_issues_assessment`.
- Present unresolved Reported Issues to Manager in result order for `approved` or `skipped` decisions.
- After the final decision, start the same implementation Work Cycle when approved undispatched Reported Issues remain. If every newly reported issue was skipped, stop in `manager_issues_assessment` without another Work Cycle.

Real QA: retain and settle at least one real issue reported by a review.

### Task 10: Run one later implementation Work Cycle

- Send approved Reported Issues from a review to `agent-worker` as one implementation Work Cycle.
- Preserve chronological Work Cycle order and original issue context.
- Let Manager create one local `Work cycle <id>` commit for the completed implementation without persisting or exposing its interim SHA. Do not push interim commits.
- Stop before another review.

Real QA: implement and commit one real approved batch reported by a review.

### Task 11: Repeat Reviewer and implementation Work Cycles

- Run an independent Reviewer review Work Cycle after every implementation Work Cycle.
- Store newly reported issues and let Manager settle them one at a time. Continue with another implementation Work Cycle when approved undispatched Reported Issues remain.
- Treat a Reviewer implementation as settled when Reviewer reports no issues or Manager skips every reported issue. If Worker review has not run, create the Review's one final Worker review Work Cycle.
- Determine whether Worker review ran from persisted Work Cycle history. Never create a second Worker review.
- If Worker reports approved issues, send them through implementation and Reviewer. Continue Reviewer-reported issue, decision, and implementation loops without a numeric limit.
- After Worker review ran, move directly to `manager_review` when Reviewer reports no issues, Manager skips every later Reviewer issue, or Manager skips every Worker-reported issue.
- Require the normal clean-tree check before each implementation or review Work Cycle. Database-only decisions and direct state progression do not require it.
- Escalate ambiguity conversationally: identify the affected Reported Issue IDs, ask the operator one precise question, and persist no decision or escalation state until clarified.

Real QA: complete repeated implementation and Reviewer loops before and after the one final Worker review, including approved and all-skipped batches, then verify the Review stops in `manager_review` with exactly one Worker review.

## Phase 4: Make Autofix durable and final

### Task 12: Rebase an active Review

- Add explicit `/skill:autofix --rebase-base [<base-ref>]` for the current project's incomplete, implemented Review. Reject a missing starting commit, no completed Worker implementation, an incomplete Work Cycle, a different current branch, or a dirty tree before fetching.
- Fetch origin, preserve the supplied ref exactly or select the stored active ref, and resolve it once to a full immutable commit SHA.
- Rebase the current branch with normal Git behavior onto the resolved SHA. Do not switch branches, push, persist pending-rebase state, persist interim Work Cycle SHAs, or automatically continue Review orchestration.
- On conflict, leave the native rebase in progress and keep Review metadata unchanged. Manager resolves unambiguous conflicts directly, asks one precise operator question before resolving an ambiguous conflict, and lets Ruby stage and continue each conflict round.
- If conflict resolution is interrupted, require the operator to run `git rebase --abort` and restart the operation. Do not support manual continuation outside Autofix.
- After full success, atomically update the active base ref/SHA and rebased Review starting commit. Preserve original base metadata and Review workflow state.
- Show the Review number, old/new active refs with full SHAs, old/new starting full SHAs, and every conflict resolution or `Resolved conflicts: none.` Stop without invoking normal Autofix resume.

Real QA: rebase one active Review onto an advanced version of the same base, one onto a different explicit base, and one through clear and ambiguous conflicts. Verify metadata, branch/remote safety, conflict reporting, and later normal Review resume.

### Task 13: Support repeated external Reviews

- Keep at most one active Review per project. Resume it before source collection; start later feedback only after it is completed.
- Group all eligible issues from one external invocation into one new Review. Create no Review when no eligible issues remain.
- Treat a GitHub comment as new only when its comment ID has never been linked to an earlier Review in the project. Ignore edits to processed IDs.
- Keep local imports source-ID-free and non-deduplicated. Every imported concern is a fresh Reported Issue, including repeated text.
- Add no reopening operation or state. The operator resubmits a concern through a new local import or a new GitHub comment.
- Continue project-scoped Review numbering across GitHub and local sources. Keep every new Work Cycle and reported issue in its Review without changing earlier history.

Real QA: complete one local Review, import another local feedback set, verify fresh issues and Review numbering, start the new Review's Work Cycle from only its inputs, and confirm another invocation resumes it without reading the source again.

### Task 14: Run Manager review and finalize

- Record Manager review as a `manager/review` Work Cycle after Reviewer has passed and the Review's one final Worker review has completed. Manager performs it inline using the complete issue history, cumulative committed diff, and Manager conversation context.
- Reuse the existing review result contract and persist Manager completion time and actual provider, model, and reasoning level when known. Resume an interrupted Manager review by performing the same incomplete Work Cycle again.
- Manager critically reviews the updates for missing requirements, contradictions, integration gotchas, incomplete work, and regressions, and may report anything else worth mentioning.
- Store Manager-reported issues with exact Work Cycle provenance. Route approved issues through Worker implementation and fresh Reviewer and Manager review without rerunning Worker review. If every Manager issue is skipped, proceed directly to finalization.
- After Manager review passes, enter `manager_finalizing`. For a project with `Gemfile`, run `bundle exec rubocop` and `bundle exec rspec` through separate non-login `bash -c` processes from the project path. Run both even when one fails. For other projects, report checks as skipped.
- A failed or interrupted check leaves the Review in `manager_finalizing` with Git and final metadata unchanged. Report both results on failure and rerun both on a later resume; do not create an issue or automatic fix.
- After checks pass, require a clean tree and require `starting_commit_sha..HEAD` to contain exactly the Review's chronological `Work cycle <id>` implementation commits.
- Store `completed_at` and complete the Review without changing its Work Cycle commits. Remove `final_commit_sha`; squash output is not workflow state.
- After completion, ask `Should i squash?`. Persist neither the question nor answer. On approval only, recheck the clean tree and exact commit sequence, then squash onto `starting_commit_sha` as local `Review N` without writing the database. Decline, failure, or success leaves the Review completed.
- Do not push or mutate a remote. The operator pushes separately.

Real QA: complete one real Manager pass and verify the Review is completed before `Should i squash?`; verify decline leaves Work Cycle commits unchanged and approval creates local `Review N` without changing the completed Review record. Exercise one Manager correction loop without a second Worker review; verify all-skipped Manager issues proceed directly; and separately verify failed checks, interrupted Manager review, an unexpected commit, and a failed optional squash all preserve completed workflow state without a push.

### Task 15: Assess Addressit replacement

- Compare actual Autofix usage with Addressit for GitHub and local sources, including repeated Reviewer and implementation loops and one final Worker review per Review.
- Add only missing behavior proven necessary by real usage.
- Decide whether Autofix can become the default.

Real QA: use Autofix for normal real GitHub and local Reviews without Addressit, or record the concrete blocker.
