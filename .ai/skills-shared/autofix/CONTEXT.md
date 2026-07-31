# Autofix terms

## Reported Issue

One concern that the operator can decide and Autofix can address. It may come from GitHub, a local review, Autowork self-review, Worker review, Reviewer review, or Manager review. A reported issue may be invalid and skipped.

## GitHub Source

An inline pull request comment fetched from GitHub. Manager turns the comment and its current code context into one self-contained reported issue before storage. Outdated, deleted, or apparently resolved code does not remove a concrete concern; the operator decides its validity.

## Local Source

A review copied from another agent. Agent-manager turns its concrete concerns into concise, self-contained reported issues. The original clipboard text is not retained.

## Autowork Source

A concern imported from Autowork self-review. One finding produces one self-contained reported issue that can enter the shared Review workflow.

## Worker Source

A finding produced by a Worker review Work Cycle. One finding produces one reported issue linked to the Work Cycle that reported it.

## Reviewer Source

A finding produced by a Reviewer review Work Cycle. One finding produces one reported issue linked to the Work Cycle that reported it.

## Manager Source

A finding produced by a Manager review Work Cycle. One finding produces one reported issue linked to the Work Cycle that reported it.

## Review

One complete cycle for a non-empty set of new GitHub, local, or Autowork feedback in one project. It contains the feedback's decisions and all Work Cycles needed to address it. It ends when one squashed commit is pushed, or when every issue is skipped and no change is needed. Empty feedback creates no Review. Later feedback starts the next Review.

## Work Cycle

One bounded implementation or review action performed by one workflow participant, with recorded input and result. Every Work Cycle belongs to one Review.

## Manager

The participant that settles reported issues, coordinates Work Cycles, creates commits, and performs the final review.

## Worker

The participant that implements approved reported issues and performs worker review Work Cycles.

## Reviewer

The participant that performs independent review Work Cycles.

## Project Path

The canonical root of the Git checkout where a reported issue belongs and work occurs.
