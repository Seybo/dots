---
name: super-review
description: >-
  Explicit-only multi-agent code review for PRs, branches, commits, staged changes,
  or diffs. Invoke only with /super-review (or /skill:super-review). Supports
  --agent claude and --agent codex, defaulting to Codex. Do not invoke for
  ordinary review requests.
---

# super-review

**Explicit invocation only:** run this skill only after `/super-review` or `/skill:super-review`. A plain request to review a PR, branch, commit, or working tree must use a direct review instead.

## Invocation

```text
/super-review [--agent claude|codex] [scope]
/skill:super-review [--agent claude|codex] [scope]
```

Default agent: `codex`. Reject missing or unsupported `--agent` values.

Both modes preserve the same reviewer roles, hard rules, phases, synthesis, report, and posting workflow:

- 3 generic adversarial reviewers
- Architecture
- Security
- Deployment
- 1 independent generic reviewer
- 2 parallel Phase 2 adjudicators

Agent implementations:

- `claude`: the original mixed Opus/Sonnet six-reviewer panel, plus the independent Codex CLI pass. Phase 2 cross-reviews Claude and Codex findings.
- `codex`: seven isolated Pi subprocesses using `openai-codex/gpt-5.6-terra` at high reasoning, all launched concurrently. Phase 2 uses two isolated `openai-codex/gpt-5.6-sol` subprocesses at high reasoning. Do not use Codex CLI native subagents; use `scripts/run-pi-reviewers`.

Codex-only convergence is same-vendor evidence and is weaker than Claude/Codex cross-vendor convergence. State that limitation in the report; do not weaken the finding verification rules.

COPYABLE OUTPUT - HARD RULE: Never use Markdown tables, ASCII tables, aligned columns, or cell-based layouts in the final report, progress updates, finding summaries, manual-verification sections, or posting preview. Use headings, bullets, and numbered finding blocks with one labeled field per line. Internal reference tables may remain as decision input, but never reproduce them in user-facing output.

## Reference files

Read each file at the phase that needs it:

- `references/hard-rules.md` — paste into every Phase 1 and Phase 2 prompt.
- `references/phase1-prompts.md` — role prompts and agent-specific launch instructions.
- `references/synthesis.md` — deduplication, Phase 2, synthesis, output, verdicts.
- `references/posting.md` — report persistence and optional pending comments.
- `references/past-findings.md` — watch entries and postmortem procedure.

## Workflow

```text
0. Selected-agent preflight.
1. Determine scope.
2. Read project CLAUDE.md + AGENTS.md from the worktree root.
3. Fetch diff + PR description when applicable.
4. Create an isolated worktree with git worktree add.
5. Phase 1: launch all seven blind reviewers concurrently and create the stable candidate manifest.
6. Phase 2: launch the applicable adversarial adjudicators concurrently; skip only empty source groups.
7. Run `scripts/validate-adjudication`; stop on invalid evidence and honor its degenerate/manual-verification result.
8. Phase 3: synthesize only validator-approved actionable candidate IDs.
9. Phase 3.5: save the report verbatim to super-review.md.
10. Phase 4: offer pending GitHub comments only in interactive mode.
11. Phase 5: remove the temporary worktree.
```

Autowork mode stops after Phase 3.5 and follows the output/status paths in its request. It never enters interactive posting.

## Step 0 — preflight

Run before scope discovery, project-file reads, diff reads, worktree creation, or reviewer launch.

### Claude mode

Use the existing Codex CLI preflight because the independent seventh reviewer uses Codex:

```bash
if ! command -v codex >/dev/null 2>&1; then
  echo "Codex executable not found"
elif codex exec --ephemeral --skip-git-repo-check --sandbox read-only \
  -m gpt-5.6-sol -c 'model_reasoning_effort="high"' \
  "Reply with exactly CODEX_PREFLIGHT_OK." 2>/dev/null | grep -Fxq "CODEX_PREFLIGHT_OK"; then
  echo "Codex preflight passed"
else
  echo "Codex preflight failed"
fi
```

If it fails, stop and ask the user to fix Codex or explicitly continue with the six Claude reviewers. On explicit continuation, skip Phase 2 and state the limitation.

### Codex mode

Verify that a fresh Pi subprocess can use the Codex provider:

```bash
pi --provider openai-codex --model gpt-5.6-terra --thinking low \
  --no-session --no-tools --no-extensions --no-skills \
  --no-prompt-templates --no-context-files --no-approve -p \
  "Reply with exactly CODEX_PREFLIGHT_OK." 2>/dev/null |
  grep -Fxq "CODEX_PREFLIGHT_OK"
```

If it fails, stop. Do not silently fall back to Claude or Codex CLI.

## Scope and context

Scope priority:

1. Explicit PR URL/number, branch, commit, base ref, staged diff, or supplied diff.
2. Feature branch: user-provided base, otherwise auto-detected `main`/`master`.
3. Main branch with staged changes: `git diff --staged`.
4. Main branch without staged changes: `git show HEAD`.

Record the exact diff base. For stacked branches, use only a full user-provided parent ref or the PR's `baseRefName`; never infer a parent from a task ID.

For PRs, fetch metadata/diff and create an isolated worktree. Never use `gh pr checkout`. Warn and offer directory scoping when a diff exceeds 2,000 lines.

Pass every reviewer:

- relevant project `CLAUDE.md` and `AGENTS.md` rules
- PR/task intent and description
- title, author, branch/base, and stack context
- full diff path
- absolute worktree path
- the complete hard-rules block

## Operational rules

- Phase 1 reviewers are blind to one another.
- Launch all seven in one parallel batch.
- In Claude mode, set every Task model explicitly per `phase1-prompts.md`.
- In Codex mode, write seven complete prompt files, then invoke `scripts/run-pi-reviewers` once with all seven paths. It starts all child processes before waiting.
- Phase 2 adjudicators are blind to each other and run concurrently when both source groups contain candidates.
- Phase 2 outputs strict JSON decisions keyed by the stable candidate IDs.
- Always run `scripts/validate-adjudication` before Phase 3; never estimate agreement ratios manually or synthesize around a failure.
- A degenerate adjudicator or NEEDS_CONTEXT decision routes candidates to Verify Manually, never the fix loop.
- Always independently verify control-flow, exception, and state-machine claims before surfacing them as High.
- `[INTENT-VERIFY]` and contested Critical findings never disappear during synthesis.
- Always save the Phase 3 report before optional posting.
- Never post to GitHub without explicit `y`/`yes`; create pending comments only.
- Never show raw reviewer output; show only synthesis.
- Always remove the temporary worktree.

## Postmortem

After the review is posted or the user adds findings, follow `references/past-findings.md`: record escaped bugs as watch entries, record ignored noise, and propose rules for repeating classes.
