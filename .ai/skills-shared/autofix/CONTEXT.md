# Autofix terms

## Reported Issue

One concern that the operator can decide and Autofix can address. It may come from GitHub, a local review, Worker review, Reviewer review, or Manager review. A reported issue may be invalid and skipped.

## GitHub Source

An inline pull request comment fetched from GitHub. Manager turns the comment and its current code context into one self-contained reported issue before storage. Outdated, deleted, or apparently resolved code does not remove a concrete concern; the operator decides its validity.

## Local Source

A review copied from another agent. Agent-manager turns its concrete concerns into concise, self-contained reported issues. The original clipboard text is not retained.

## Worker Source

A reported issue produced by a Worker review Work Cycle and linked to that exact Work Cycle.

## Reviewer Source

A reported issue produced by a Reviewer review Work Cycle and linked to that exact Work Cycle.

## Manager Source

A reported issue produced by a Manager review Work Cycle and linked to that exact Work Cycle.

## Review

One complete cycle for a non-empty set of new GitHub or local feedback in one project. It contains the feedback's decisions and all Work Cycles needed to address it. It ends when Autofix creates one local squashed commit, or when every issue is skipped and no change is needed. Autofix does not push. Empty feedback creates no Review. Later feedback starts the next Review.

## Work Cycle

One bounded implementation or review action performed by one workflow participant, with recorded inputs, completion provenance, and any Reported Issues. Every Work Cycle belongs to one Review.

## Manager

The participant that settles reported issues, coordinates Work Cycles, creates commits, and performs the final review. Manager is deliberately critical: it actively looks for missing requirements, contradictions, gotchas, incomplete work, and regressions instead of acting as a passive router. The operator still makes reported-issue decisions.

## Worker

The participant that implements approved reported issues and performs one final Worker review Work Cycle per Review after Reviewer reports no issues. If that Worker review reports issues, Reviewer reviews the later implementation and Worker does not review again.

## Reviewer

The participant that performs independent, context-aware review Work Cycles. Reviewer evaluates the implementation commit together with relevant surrounding code and affected flows so fixes do not introduce regressions elsewhere.

## Project Path

The canonical root of the Git checkout where a reported issue belongs and work occurs.
