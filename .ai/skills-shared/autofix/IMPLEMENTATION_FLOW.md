# Autofix implementation flow

## Purpose

Build Autofix through small vertical increments. At the end of every task:

- `/skill:autofix` is runnable.
- Backward compatibility with earlier increments is not assumed. During each
  task's grilling session or when planning implementation, explicitly decide
  which existing inputs and behaviors are retained, replaced, or removed.
- The task adds one useful feature or improvement.
- RSpec and RuboCop pass for the implemented Ruby behavior.
- The new external behavior is manually QAed through Pi against a real GitHub
  pull request or real local clipboard review, as the task requires.

Do not test `gh`, `git`, or `tmux` behavior through complex stubs. Real-PR QA is
the integration test for GitHub boundaries. Real clipboard extraction must be
QAed through the manager model in Pi; deterministic Ruby persistence and
validation receive automated specs.

Before implementing each task:

1. Run a grilling session limited to that task.
2. Store the task-specific decisions in its task folder.
3. Reference `DEVELOPMENT_PRINCIPLES.md` from the task.
4. Split the task again if grilling reveals more than one substantial integration
   boundary.

## Phase 1: Read and retain reported issues

### Task 1: Fetch one comment

- Accept one inline GitHub comment URL.
- Fetch and print that comment.
- Create only the minimum runnable Autofix skill and Ruby CLI needed for this
  behavior.

Real QA: run Autofix against one real inline-comment URL and verify the displayed
comment.

### Task 2: Discover the current PR

- Replace the supplied comment URL interface with current-branch pull request
  discovery.
- Remove the single-comment URL behavior from Task 1.
- Retrieve the discovered pull request's inline review comments.
- Display only the first comment returned by GitHub, then stop. Do not add
  ordering behavior or pull request metadata output.

Real QA: run Autofix without arguments inside a checkout whose branch has a real
pull request and verify that only the first returned inline comment is displayed.

### Task 3: Persist GitHub reported issues

- Add SQLite, Sequel, migrations, and one generic `reported_issues` table.
- Give every table an integer primary ID and creation timestamp while enforcing
  issue domain identity separately by canonical project path, source, and source
  ID; retain the current unresolved body and nullable decision.
- Automatically migrate, fetch every inline-comment page, insert new GitHub
  issues, and refresh the bodies of unresolved existing issues.
- Leave decided issues unchanged, then select unresolved stored GitHub issues
  whose IDs occur in the fresh current-PR response and display the first current
  GitHub comment.
- Print `No unresolved comments.` when that queue is empty.
- Add no temporary inspection command; verify storage with real SQLite specs and
  the complete path through Pi.

Real QA: run Autofix against a real pull request and verify the fetch, persist,
select, and display path while real SQLite specs verify stored data.

### Task 4: Import local reported issues

- Add `/skill:autofix --local` while retaining no-argument GitHub behavior.
- Let agent-manager read `pbpaste`, extract every concrete concern, ignore
  non-issue prose, and rewrite each issue into a concise, self-contained body.
- Pass issue bodies to Ruby through a temporary JSON array and delete the file
  after import.
- Persist every issue separately with source `local`, no source ID, and the
  canonical current project path. Do not store or deduplicate the clipboard.
- Select the current project's unresolved local issues by database ID ascending.

Real QA: import a real multi-issue agent review through Pi, verify non-issue prose
is excluded, and inspect each retained local issue.

## Phase 2: Address one reported issue

### Task 5: Record one decision

- Present one unresolved reported issue at a time, regardless of source.
- Record `approved` or `skipped` for the displayed issue.
- Display the next issue only after the operator decides the current one.
- Show the stored decision through Autofix.

Real QA: classify one real GitHub issue and one real local issue and confirm that
both use the same decision queue.

### Task 6: Run the worker

- Generate the structured Markdown prompt for one approved reported issue.
- Include its project path, body, and current GitHub context when available.
- Send it to `agent-worker` and collect worker completion.

Real QA: have `agent-worker` modify code for one approved real reported issue.

### Task 7: Run one reviewer pass

- Send the worker's change to `agent-reviewer`.
- Collect and display one pass/fail result.
- Stop when the reviewer reports findings; do not implement corrections yet.

Real QA: have `agent-reviewer` inspect a real worker change and return a result.

### Task 8: Finalize one successful issue

- Add final operator approval.
- Create the local commit for a successful one-issue run.

Real QA: complete one real reported issue from ingestion through an approved local
commit.

## Phase 3: Expand the shared workflow

### Task 9: Process a batch

- Approve or skip multiple reported issues from one active GitHub PR or local
  review.
- Send approved issues to the worker as one coherent batch.

Real QA: process multiple issues from one real GitHub PR or one real local review.

### Task 10: Capture structured reviewer findings

- Persist reviewer findings.
- Display them to the operator.
- Stop without fixing them.

Real QA: use a real change where `agent-reviewer` reports at least one finding.

### Task 11: Add the correction loop

- Send accepted findings to `agent-worker`.
- Apply corrections.
- Request another reviewer pass.
- Escalate disagreement or ambiguity to the operator instead of importing the
  old Addressit debate machinery automatically.

Real QA: complete one real reviewer-requested correction and second review.

## Phase 4: Make Autofix a daily driver

### Task 12: Add interruption and resume

- Resume durable manager, worker, and reviewer handoffs for either issue source.
- Provide read-only run status.

Real QA: terminate and resume a real run while it is waiting at an agent handoff.

### Task 13: Support repeated review rounds

- Remember addressed and skipped reported issues from either source.
- Select only new or reopened feedback during later GitHub fetches or local
  imports.

Real QA: process at least two review rounds from one real source without
reselecting terminal issues.

### Task 14: Add final checks

- Run configured checks before final approval and commit.
- Report failures without speculative recovery behavior.

Real QA: complete one real round with passing checks and separately confirm that
an intentionally failing check stops finalization.

### Task 15: Assess Addressit replacement

- Compare actual Autofix usage with the existing Addressit workflow for both
  GitHub and local review sources.
- Add only missing features proven necessary by earlier QA.
- Decide whether Autofix can become the default.

Real QA: use Autofix for normal real GitHub and local review rounds without
falling back to Addressit, or record the concrete remaining blocker.
