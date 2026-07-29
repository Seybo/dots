# Autofix implementation flow

## Purpose

Build Autofix through small vertical increments. At the end of every task:

- `/skill:autofix` is runnable.
- Backward compatibility with earlier increments is not assumed. During each
  task's grilling session or when planning implementation, explicitly decide
  which existing inputs and behaviors are retained, replaced, or removed.
- The task adds one useful feature or improvement.
- RSpec and RuboCop pass for the implemented Ruby behavior.
- The new behavior is manually QAed against a real GitHub pull request.

Do not test `gh`, `git`, or `tmux` behavior through complex stubs. Real-PR QA is
the integration test for those boundaries.

Before implementing each task:

1. Run a grilling session limited to that task.
2. Store the task-specific decisions in its task folder.
3. Reference `DEVELOPMENT_PRINCIPLES.md` from the task.
4. Split the task again if grilling reveals more than one substantial integration
   boundary.

## Phase 1: Read real PR feedback

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
- List the discovered pull request's inline review comments.

Real QA: run Autofix without a URL inside a checkout whose branch has a real pull
request.

### Task 3: Persist fetched comments

- Add SQLite, Sequel, migrations, and the agreed database structure.
- Store fetched comments.
- Expose enough Autofix output to inspect the persisted result.

Real QA: fetch a real pull request and inspect its persisted comments through
Autofix.

## Phase 2: Address one comment

### Task 4: Record one decision

- Select one fetched comment.
- Record `approved` or `skipped`.
- Show the stored decision through Autofix.

Real QA: classify one real comment and confirm that Autofix reports the decision.

### Task 5: Run the worker

- Generate the structured Markdown prompt for one approved comment.
- Send it to `agent-worker`.
- Collect worker completion.

Real QA: have `agent-worker` modify code for one approved real PR comment.

### Task 6: Run one reviewer pass

- Send the worker's change to `agent-reviewer`.
- Collect and display one pass/fail result.
- Stop when the reviewer reports findings; do not implement corrections yet.

Real QA: have `agent-reviewer` inspect the real worker change and return a result.

### Task 7: Finalize one successful comment

- Add final operator approval.
- Create the local commit for a successful one-comment run.

Real QA: complete one real comment from fetch through an approved local commit.

## Phase 3: Expand the usable workflow

### Task 8: Process a batch

- Approve or skip multiple comments.
- Send approved comments to the worker as one coherent batch.

Real QA: process multiple comments from one real pull request.

### Task 9: Capture structured reviewer findings

- Persist reviewer findings.
- Display them to the operator.
- Stop without fixing them.

Real QA: use a real change where `agent-reviewer` reports at least one finding.

### Task 10: Add the correction loop

- Send accepted findings to `agent-worker`.
- Apply corrections.
- Request another reviewer pass.
- Escalate disagreement or ambiguity to the operator instead of importing the
  old Addressit debate machinery automatically.

Real QA: complete one real reviewer-requested correction and second review.

## Phase 4: Make Autofix a daily driver

### Task 11: Add interruption and resume

- Resume durable manager, worker, and reviewer handoffs.
- Provide read-only run status.

Real QA: terminate and resume a real run while it is waiting at an agent handoff.

### Task 12: Support repeated PR rounds

- Remember addressed and skipped comments.
- Select only new feedback during later invocations.

Real QA: process at least two review rounds on one real pull request.

### Task 13: Add final checks

- Run configured checks before final approval and commit.
- Report failures without speculative recovery behavior.

Real QA: complete one real round with passing checks and separately confirm that
an intentionally failing check stops finalization.

### Task 14: Assess Addressit replacement

- Compare actual Autofix usage with the existing Addressit workflow.
- Add only missing features proven necessary by earlier QA.
- Decide whether Autofix can become the default.

Real QA: use Autofix for a normal real review round without falling back to
Addressit, or record the concrete remaining blocker.
