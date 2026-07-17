---
name: claude-super-fix
description: Command-only companion to claude-super-review. Use only when the user invokes /claude-super-fix to verify and address findings from a saved super-review.md report or pasted external review feedback. Applies only real, in-scope fixes; rejects noise and scope creep; never stages, commits, pushes, changes branches, stashes, or edits PR/MR metadata.
---

# claude-super-fix

Companion skill for `/claude-super-review`.

Use this only when the user explicitly invokes:

- `/claude-super-fix`
- `/claude-super-fix <path-to-super-review.md>`
- `/claude-super-fix <pasted findings>`

Do not trigger implicitly for generic review, fix, or PR-feedback requests.

## Purpose

Take review findings from `super-review.md` or pasted external feedback and turn only the real, in-scope findings into code changes.

Treat every finding as a claim to verify, not an instruction to obey. Apply only findings that are real, relevant to the current PR/task, and worth changing. Explicitly skip noise, taste-only nits, speculative follow-ups, and behavior changes that conflict with user intent, repo conventions, or PR scope.

## Inputs

Preferred input:

1. The saved `/claude-super-review` report:
   - task-folder `super-review.md`, when known
   - repo-root `super-review.md`, when no task folder is known
   - explicit path passed by the user
2. Pasted findings from Claude, CodeRabbit, GitHub review comments, or another external reviewer.

When no report or pasted findings are available, ask the user for the `super-review.md` path or the findings to process.

## Hard safety rules

- Do not stage files.
- Do not commit.
- Do not amend commits.
- Do not push.
- Do not change branches.
- Do not create, delete, rename, or reset branches.
- Do not stash, apply, pop, or drop stashes.
- Do not edit PR/MR title, body, labels, reviewers, comments, or status.
- Do not open, approve, close, merge, or submit a PR/MR.
- Do not overwrite or revert user changes.

Editing working-tree files to implement approved fixes is allowed. Git and PR/MR state mutation is not.

## Workflow

### 1. Preserve current context

- Read the user request and the full review input.
- Resolve the current repo, branch, base branch, and local status when available.
- Read repo instructions such as `AGENTS.md`, `CLAUDE.md`, or task instructions before editing.
- Inspect current working-tree changes before patching so user changes are not overwritten.

### 2. Build an adjudication list

Split the review into distinct findings. For each finding, classify it as exactly one of:

- `fix` - real, in scope, worth changing now.
- `skip` - not real, not useful, too speculative, or style-only.
- `intent-needed` - likely requires a behavior/product decision.
- `already-fixed` - current code already addresses it.
- `out-of-scope` - valid concern, but outside the PR/task scope.
- `follow-up` - valid future cleanup that should be reported, not patched now.

Verify each non-trivial claim against code, tests, docs, and the PR diff before editing. Prefer source evidence over reviewer severity. A `HIGH` label from a reviewer is still only a claim.

### 3. Respect `/claude-super-review` report structure

`/claude-super-review` can produce:

- High-confidence findings.
- Single-agent specialist findings.
- Architecture findings.
- Intent-verification findings.
- Contested Criticals.
- Verify Manually items.

Handle them as follows:

- High-confidence does not mean auto-fix. Re-check the code and patch only if the finding is still real and in scope.
- Intent-verification findings require checking the task/PR intent. If behavior intent is unclear and a fix would change behavior, mark `intent-needed` instead of guessing.
- Contested findings must be independently verified. If the dispute cannot be resolved from source evidence, mark `intent-needed` or `follow-up`; do not patch blindly.
- Verify Manually items must be manually verified from the code, tests, or docs before any patch. If verification is not possible, do not patch.
- Critical/HIGH severity raises priority, but does not override verification.

### 4. Architecture findings

Architecture findings from `/claude-super-review` are expected and valid review material. They still need source verification.

Fix now when:

- The PR introduced or materially grew a God file, God class, or God function.
- The code is in the wrong layer or directory according to repo conventions.
- Pure logic is tangled with IO/network/filesystem/rendering and the split is small enough to do safely inside this PR.
- Duplication introduced by this PR clearly wants a shared helper/module and the extraction is low-risk.

Skip when:

- The finding is only personal organization preference.
- The file/function is small or single-purpose.
- The issue is pre-existing and not materially worsened by this PR.
- The proposed architecture does not match the repo's existing conventions.

Mark `follow-up` when:

- The architecture concern is real, but fixing it would be a broad refactor.
- The split is valuable but too risky for the current PR/task.
- The right target architecture needs product/domain confirmation.

### 5. Decide what to fix

Fix:

- Correctness bugs.
- Real regressions.
- Missing compatibility for changed behavior.
- Broken tests.
- Unsafe behavior.
- Test gaps that protect changed behavior.
- Small maintainability fixes that remove real ambiguity or duplicated/dead paths in touched code.

Skip:

- Pure style preferences.
- Broad refactors unrelated to the PR/task.
- Speculative future work.
- Unrelated security hypotheticals.
- Consumer-side issues outside this PR unless the user explicitly asks.
- Suggestions that conflict with repo conventions or task requirements.

For intent questions, infer from the task and surrounding code when the answer is clear. Ask the user only when changing behavior would be risky.

### 6. Patch narrowly

- Keep changes inside the PR/task scope and touched ownership boundaries.
- Use existing project patterns and helpers.
- Avoid expanding the feature just to satisfy a reviewer suggestion.
- Do not add `Signed-off-by` unless the current user or repo task explicitly requires it.
- Prefer focused edits over rewrites.

### 7. Verify

- Run focused tests/checks for changed areas first.
- Run broader checks only when shared code, public behavior, or cross-module contracts changed.
- If a full suite is blocked by environment restrictions, report the blocker clearly.
- Do not claim verification passed unless the command actually completed successfully.

## Follow-ups output

Some findings may be valid but intentionally not patched. Do not edit the PR/MR body. Do not create GitHub/GitLab issues.

Instead, print a `Follow-ups` section in the final response with self-contained bullets:

```text
## Follow-ups
- <what is wrong> - <file/area>; proposed: <future fix>; source: <review input/report item>
```

Only include real future cleanup here. Do not include nits, rejected findings, or task-spec decisions that are not debt.

## Final report

End with a compact report:

- Fixed: what changed.
- Skipped: what was deliberately rejected and why.
- Intent needed: decisions the user must make, if any.
- Follow-ups: valid future cleanup printed as bullets, not written anywhere else.
- Verification: commands and results.
- Git state: mention that nothing was staged, committed, pushed, or otherwise mutated.

Do not paste the entire adjudication table unless the user asks. Mention only decisions that affect the outcome.
