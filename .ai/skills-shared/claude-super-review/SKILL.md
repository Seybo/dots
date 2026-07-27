---
name: claude-super-review
description: >-
  Explicit-only multi-agent code review for PRs, branches, commits, staged changes,
  or diffs. Invoke only with /claude-super-review (or its exposed short alias).
  Do not invoke for ordinary review requests; handle those with a direct review
  unless the user explicitly requests this workflow.
---

# code-review

**Explicit invocation only:** run this skill only after `/claude-super-review` (or its exposed short alias). A plain request to review a PR, branch, commit, or working tree ("review the last commit", "review PR 247", a bare PR URL) must NOT invoke this skill — handle those directly. No implicit invocation.

Multi-agent code review: 6 parallel Claude subagents (a mixed Opus+Sonnet panel, model set EXPLICITLY in each Task call) plus a Codex pass on the same diff, filtered via convergence, returning a ranked list with verdict. Optimized for AI-generated code where single-pass review misses blind spots, for cross-cutting issues narrow specialists skip, and for structural issues that need an architecture lens.

**Empirically: generic broad-mandate agents find more cross-cutting issues than narrow specialists** — specialization is kept only for Architecture, Security, and Deployment, where the narrow lens earns its panel slot.

## Reference files (read at the phase that needs them, not upfront)

- `references/hard-rules.md` — the HARD RULES BLOCK pasted into EVERY reviewer prompt (Phases 1 and 2).
- `references/phase1-prompts.md` — model assignment table (locked by Sasha), the 4 subagent prompt templates, Codex invocation + pitfalls.
- `references/synthesis.md` — dedup/convergence rules, Phase 2 cross-review prompts, Phase 3 decision tree, output format, verdict guidelines.
- `references/posting.md` — Phase 3.5 report saving, Phase 4 pending-comment mechanics, the LOCKED "Variant A" comment format, PRE-POST GATE.
- `references/past-findings.md` — escaped-bug rubric: `watch` entries get appended to Phase 1 prompts; postmortem procedure lives there.

## Workflow

```
0. Codex preflight (below) — before scope, diff, worktree, or any reviewer.
1. Determine scope (PR URL / branch / staged / last commit).
2. Read project CLAUDE.md + AGENTS.md from the worktree root.
3. Fetch diff + PR description (if PR).
4. Create an isolated worktree via `git worktree add` — subagents must read
   FILES for real line numbers, and the user's working dir stays untouched.

PHASE 1  — read references/hard-rules.md + references/phase1-prompts.md +
           the watch entries in references/past-findings.md.
           Launch in ONE message, all blind to each other:
           3 generic adversarial subagents (2x opus + 1x sonnet),
           Architecture (sonnet), Security (opus), Deployment (sonnet),
           + Codex via background Bash (only after a passed preflight).
PHASE 2  — read references/synthesis.md. Adversarial cross-review, parallel,
           only when Codex completed: Claude judges codex_findings (opus),
           Codex judges claude_findings.
PHASE 3  — synthesis per the decision tree in references/synthesis.md.
           [INTENT-VERIFY] always surfaces; contested Criticals never drop.
PHASE 3.5 — read references/posting.md. ALWAYS save the full Phase 3 markdown
           verbatim to super-review.md (task folder if known, else repo root);
           print the path.
PHASE 4  — interactive posting per references/posting.md: ask which findings,
           leave PENDING inline comments (Variant A format), never submit.
PHASE 5  — cleanup: git worktree remove <dir> (--force if busy).
```

## Step 0 — Codex preflight (must run first)

Before determining scope, reading project files or the diff, creating a worktree, or launching any reviewer:

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

If it fails, stop before any review work and ask the user to fix Codex and rerun, or explicitly choose **continue without Codex**. Do not print raw preflight output (may contain auth details). Only on an explicit user choice, record `Codex status: skipped by user`, run the 6 Claude reviewers only, skip Phase 2, use Claude-only convergence, and state that limitation in the report. If it passes, record `Codex status: passed`.

## Step 1 — Determine scope

Priority:
1. **User stated explicitly** (PR number/URL, branch, commit SHA, or full base branch/ref) — use what they said.
2. **On a feature branch** — with a user-provided base, `git diff <base>...HEAD`; otherwise `git diff main...HEAD` (or `master`, auto-detected via `gh repo view`).
3. **On main with staged changes** — `git diff --staged`.
4. **On main with no staged changes** — `git show HEAD`.

Record the exact diff base used. For stacked branches, never infer a parent from a task/story ID; only use a non-main parent when the user provided the full branch/ref. Take the base from `gh pr view ... --json baseRefName`, not from assumption.

If a PR URL is provided:
```bash
gh pr view <num_or_url> --json title,body,files,headRefName,baseRefName,author
gh pr diff <num> > /tmp/pr<num>.diff
BRANCH=$(gh pr view <num> --json headRefName -q .headRefName)
git fetch origin "$BRANCH"
git worktree add "/tmp/pr<num>_worktree" "origin/$BRANCH"
```

Use `git worktree add`, never `gh pr checkout` (it blocks parallel reviews in the main working dir). Subagents get the worktree as an absolute path.

If the diff is >2000 lines, warn the user and offer a split ("Run the full review or scope by directory?"). The skill still runs but fidelity drops.

## Step 2 — Gather context for subagents

Pass to every subagent prompt:
1. **Project CLAUDE.md + AGENTS.md** from the worktree root (if >300 lines, extract only severity rules, hard rules, and codebase quirks — don't dump everything).
2. **PR description** — intent verification depends on it.
3. **PR title + author + branch stack info** — stacked PRs carry parent-PR dependencies.
4. **Worktree absolute path**.

## Hard rules (operational)

- Phase 1 reviewers (6 Claude + Codex) are blind to each other — otherwise anchoring bias.
- All Phase 1 calls launch in a single message (7 with Codex, 6 without). Sequential = slower and less independent.
- `model` explicit in EVERY Task call per the table in `references/phase1-prompts.md`. Inheriting the session model is forbidden.
- HARD RULES BLOCK + project conventions in EVERY prompt.
- Worktree before subagents; cleanup in Phase 5 so worktrees don't accumulate.
- [INTENT-VERIFY] and contested Criticals are never dropped at synthesis.
- Always save the Phase 3 report (Phase 3.5) before posting.
- Senior architect voice in output: direct, no hedging, no preambles, no emoji.
- Never post to GitHub without an explicit y/yes; pending only, never submit.
- Verdict strictly by the rules in `references/synthesis.md` — no sycophancy.

## What NOT to do

- Do not show subagent raw output — only synthesized.
- Do not offer "add a TODO"/"add a comment" suggestions, flag naming a linter catches, or propose stylistic rewrites of working code.
- Do not produce one-sentence findings or cite diff hunk positions as line numbers.
- Do not run the legacy 5-specialist panel (Logic/Security/Tests/Perf/Deploy); the current setup is 3 generic + Architecture + Security + Deployment.

## Postmortem hook (after each review)

After the user has posted the review or added their own comments, run the postmortem procedure in `references/past-findings.md`: log what they caught that the skill missed (gaps → `watch` entries), what the skill produced that they ignored (noise), and propose encoding for any repeating class.
