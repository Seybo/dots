---
name: claude-super-review
description: Multi-agent code review for PR / branch / diff in any repo. Runs 6 parallel Claude subagents (4 generic adversarial + 1 Security + 1 Deployment) + an independent Codex pass. Convergence filter (≥2 agents confirmed = valid issue; Critical/HIGH = always surfaced). Surface Critical / High / Medium with mandatory short writeup "what's wrong / code / why it matters / fix". Senior architect voice, output ready to paste into a GitHub comment. Command-only skill. Invoke only when the user explicitly writes `/claude-super-review`.
---

# claude-super-review

Multi-agent code review skill - runs 6 parallel Claude subagents and a Codex pass on the same diff, filters via convergence, returns a ranked list with verdict. Optimized for AI-generated code where single-pass review misses blind spots, and for cross-cutting issues that narrow specialists skip over.

## When to trigger

Only these should trigger the skill:
- `/claude-super-review`
- `/claude-super-review 247`
- `/claude-super-review feature-branch`

Never trigger for plain review requests such as:
- `review the last commit`
- `review PR 247`
- `review my branch`
- `look at what X pushed`
- a GitHub PR URL alone
- requests to review uncommitted changes

**No implicit invocation. No invocation by any other means.**

## Workflow (high-level)

```
1. Determine scope (PR URL / branch / staged / last commit)
2. Read project CLAUDE.md + AGENTS.md if present
3. Fetch diff + PR description (if PR)
4. IMPORTANT: create an isolated worktree via `git worktree add` - subagents must
   read FILES, not only the diff (otherwise line numbers will be diff hunk
   positions). The worktree preserves parallelism across multiple PR reviews -
   the user's current working dir stays untouched.

PHASE 1 - Independent reviews (parallel, blind to each other):
   - 4 Generic adversarial subagents (no role bias) → broad coverage
   - 1 Security subagent → secrets / PII / injection / regex completeness
   - 1 Deployment subagent → migrations / env vars / PR description structure
   - 1 Codex independent pass → cross-vendor signal

PHASE 2 - Adversarial cross-review (parallel):
   - Claude reviews each codex_finding: AGREE / DISAGREE / NEEDS_CONTEXT
   - Codex reviews each claude_finding (post-convergence): AGREE / DISAGREE / NEEDS_CONTEXT

PHASE 3 - Synthesis (main agent):
   - 2+ agents flagged the same issue → surface high-confidence
   - 1 agent flagged Critical/HIGH → surface
   - 1 agent flagged Medium → drop unless interesting
   - Intent-verification findings always surface

PHASE 4 - Offer to post in a GitHub PR comment via the gh CLI
PHASE 5 - Cleanup worktree
```

**Empirically: 4 generic agents find more cross-cutting issues than 4 specialized ones.** Specialized prompts force each agent to think only within its niche (a Logic agent won't think "approval gate compares a different field from the idempotency key" - that requires cross-lens reasoning). Give the generics a mandate of "find anything wrong" and they naturally cluster around the issues that actually matter. Specialization is kept only for Security (where legal/compliance domain knowledge is critical) and Deployment (the PR-description gap - a structural check).

## Step 1 - Determine scope

Priority:
1. **User stated explicitly** (PR number/URL, branch, commit SHA) - use what they said.
2. **On a feature branch** - `git diff main...HEAD` (or `master`, auto-detected via `gh repo view`).
3. **On main with staged changes** - `git diff --staged`.
4. **On main with no staged changes** - `git show HEAD`.

If a PR URL is provided:
```bash
gh pr view <num_or_url> --json title,body,files,headRefName,baseRefName,author
gh pr diff <num> > /tmp/pr<num>.diff

# Create an isolated worktree - leaves the current working dir alone so you can
# review other PRs in parallel.
BRANCH=$(gh pr view <num> --json headRefName -q .headRefName)
git fetch origin "$BRANCH"
WORKTREE_DIR="/tmp/pr<num>_worktree"
git worktree add "$WORKTREE_DIR" "origin/$BRANCH"
```

Subagents get `$WORKTREE_DIR` as an absolute path and read files from there. The user's main working dir stays untouched - they can work on another PR or main branch in parallel.

**Cleanup in Phase 5** (after the review):
```bash
git worktree remove "$WORKTREE_DIR"
```

## Step 2 - Gather context for subagents

Pass to every subagent in the prompt:

1. **Project CLAUDE.md** + **AGENTS.md** from the worktree root - project conventions, severity rules.
2. **PR description** - so intent verification works (if the diff changes a constant but the description doesn't mention it, that's a red flag).
3. **PR title + author + branch stack info** - on stacked PRs ('user/branch-XXXXX/...->bootstrap') don't forget dependencies from the parent PR.
4. **Worktree absolute path** - so subagents open the right files (must be absolute, not relative).

If project CLAUDE.md is >300 lines, extract only the relevant sections (severity rules, codebase quirks, project-specific don'ts). Don't dump everything into every prompt.

## Phase 1 - Independent reviews (parallel)

Launch **7 parallel** calls in a single message: 4 generic Task calls + 1 Security Task + 1 Deployment Task + Codex (via Bash background).

**Hard prompt rules** (apply to ALL subagent prompts):

```
LOCATION CITATIONS - HARD RULE:
- ALWAYS open the actual file via Read tool before citing a location.
- Cite file-line numbers from the actual file as it exists in the worktree.
- NEVER cite diff hunk positions, diff line numbers, or "+N" annotations.
- If the diff shows a change without showing the surrounding file, OPEN the file first.
- Format: `path/to/file.rb:NN-MM` (range OK) or `path/to/file.rb:NN`.
- Wrong: "spec/foo.rb:4075" if the file is only 300 lines long.
- All file paths are relative to the worktree root: <WORKTREE_DIR>
- This is non-negotiable: bad line numbers waste reviewer time and undermine trust.

FORMAT OF EACH FINDING - HARD RULE (no one-liners):
[SEVERITY][category] path/to/file.ext:NN-MM - short headline (one sentence)

What: 2-4 sentences. Quote the actual code (1-3 lines) so the reader sees the
issue without opening the file. Explain the contradiction or failure scenario in
concrete terms. If the bug is conditional, state the conditions.

Why it matters: 1-2 sentences. Real consequence (data loss, double-spend, P0
silent failure, regression on documented behavior). Skip "could be cleaner".

Fix: concrete code-level suggestion. Not "consider X" - say "change Y to Z" or
"add CHECK constraint on (col1, col2)" or "rewrite as multi_insert_conflict".

If you cannot follow this format, your finding will be dropped at synthesis.

INTENT VERIFICATION:
For ANY behavior change in the diff that is NOT explicitly called out in the PR
description (constants, defaults, thresholds, validity periods, retry counts,
log levels, environment variable names, default scopes), surface as:
  [INTENT-VERIFY] file:line - "<old value> → <new value>" not mentioned in PR
  description. Confirm intent with author.
This is mandatory even if the change looks safe. The PR description is the
author's contract - silent changes need explicit confirmation.

DOMAIN KNOWLEDGE:
If the PR touches a well-known third-party API/SDK, think about KNOWN limits
and quirks BEFORE checking generic correctness. Examples:
- Apollo.io: 50k results / 500-page hard cap, after ~25k results duplicates
  and garbage. /mixed_companies/search requires X-Api-Key header.
- Stripe: idempotency keys live 24h, webhooks need signature verification.
- GitHub API: 5000 req/h authenticated, secondary rate limits, conditional
  requests via ETag/If-None-Match.
- OpenAI: tokens != characters, response truncation at max_tokens, streaming
  needs reconnect logic.
- AWS SDK: pagination via continuation tokens, S3 eventual consistency on
  list-after-write, IAM permission boundary subtleties.
If PR uses one of these without respecting the limit/quirk, flag it.

CROSS-FIELD CONSISTENCY:
Look for cases where two related operations use DIFFERENT fields to identify
the same thing. Examples:
- Approval gate filters by `campaign_id` but idempotency key is built from
  `campaign_id + config_hash + page + per_page` - one approval covers infinite
  filter changes.
- Reservation uses `idempotency_key` but reuse check uses `request_hash` -
  cache inconsistency.
- Write to column A, read from column B.
- Cache key includes timestamp but lookup omits it.
Surface these as [HIGH] - they are the kind of bug that survives review by
single-lens specialists.

SKIP LIST (do not surface these as findings):
- Formatting, whitespace, line breaks (linter catches)
- Naming preferences (Rubocop/eslint catches)
- "Consider adding a comment"
- "Could be extracted to a helper" (unless 4+ duplications)
- Suggestions to add tests for trivial getters
- Pre-existing bugs not introduced by THIS diff
```

### Subagent prompts

**Subagents 1-4: Generic adversarial reviewers**

Identical prompt for all four (this is intentional - same prompt, 4 separate runs, gives 4 independent signal sources):

```
You are a senior code reviewer. You have full mandate to find what is wrong
with this PR. No specific lens, no narrow focus - just find what's broken,
unsafe, or contradictory.

[INSERT HARD RULES BLOCK above - location citations, format, intent
verification, domain knowledge, cross-field consistency, skip list]

PR context:
- Title: <PR title>
- Author: <name>
- Branch: <head> → <base> (note if stacked PR)
- Stats: <additions>+ / <deletions>- across <N> files
- Description: <PR body or summary>

Project conventions:
<paste relevant sections of project CLAUDE.md + AGENTS.md>

You have access to:
- /tmp/pr<num>.diff (full diff, 4000+ lines OK)
- Worktree at <WORKTREE_DIR> - all files relative to this path. Open files
  via Read using <WORKTREE_DIR>/path/to/file.rb (absolute path).

Your process:
1. Skim the diff to understand WHAT this PR is doing.
2. Read the PR description - what does the author claim?
3. For each non-trivial file change, OPEN the file (via Read) - never review
   from diff alone. Diff hunk positions are not line numbers.
4. Look for contradictions: PR claims X, code does Y. Description silent on Z.
5. Look for cross-field consistency: if file A reads from column C, does
   file B write to column C? If approval is stored with field X, is approval
   check filtering by field X?
6. Look for known-API quirks (see DOMAIN KNOWLEDGE block).
7. Look for behavior changes (constants, defaults) not in PR description -
   surface as [INTENT-VERIFY] regardless.

Output a complete list of findings in the required format. If no issues,
say "No findings" explicitly. End with "Verdict: <clean | N findings>".
```

**Subagent 5: Security focus**

```
You are a senior security reviewer.

[INSERT HARD RULES BLOCK]

Look for:
- Secrets / API keys committed to code, logs, error messages, stack traces
- Sensitive data (PII, prospect emails, internal IDs) logged outside sanctioned
  structured storage (per AGENTS.md state/ dir, etc.)
- Injection: SQL via string interpolation, command via shell escape, JSON
  injection via untrusted input
- Authentication / authorization bypass (missing checks on endpoints, scope
  confusion - e.g. permission for resource X checked against resource Y)
- Crypto misuse (weak hash, hardcoded IV, predictable random, plaintext password)
- Insecure deserialization (YAML.load, Marshal.load, pickle in Python, eval)
- TLS misconfig (verify_mode = NONE, http:// where should be https://, cert
  pinning bypass)
- Path traversal, SSRF, open redirects
- Regex DoS (catastrophic backtracking on user input)
- Race conditions in auth-critical paths (TOCTOU)

Sensitivity-of-redaction analysis:
- If diff adds/changes a redaction regex (sanitize / scrub / mask function),
  TEST IT MENTALLY against real-world adversarial inputs:
    - JSON-style values: "api_key": "value"
    - Header-style: X-Api-Key: value, Authorization: Token foo
    - URL-style: ?api_key=value&secret=...
    - Standalone: bearer abc, refresh_token=..., private_key=...
  List what the regex MISSES, name the specific tokens not covered.

- If diff adds/changes a secret-key block-list (reject configs containing
  secret-looking keys), TEST IT against:
    - bearer, refresh_token, private_key, signing_key, client_secret
    - jwt, session_token, oauth_token
    - Variations: refreshToken, RefreshToken, refresh-token
  List specific keys the regex misses.

Project conventions: <paste>
PR context: <paste>

Process as in generic prompt. Find what's wrong.
```

**Subagent 6: Deployment + PR-description structure**

```
You are a senior deployment reviewer.

[INSERT HARD RULES BLOCK]

Diff focus:
- Migrations: locks tables under load? backwards-compatible with running code?
  reversible (has down block)? if SQLite, do the DDL changes actually run?
  Trace migration runner path - is it in the routine deploy procedure or only
  one-time setup?
- New env vars: documented? checked at deploy time (health check)? failure mode
  if missing - early raise or deferred?
- Breaking API changes: public endpoints, exported functions, response shapes
- Deployment ordering: config-before-code? data backfill needed?
- Feature flag missing where rollback would otherwise need revert
- Observability gaps (new failure mode, no logs / metrics / alerts)
- Stacked PR ordering: if this PR is stacked on another, will it deploy
  independently? Or only after parent merges?
- Behavior changes (validity periods, retry counts, thresholds) - DO they
  appear in PR description? If silent, surface as INTENT-VERIFY.

PR description structural check (STRUCTURE not prose):
- For migration PRs - description must say HOW to run migration on prod
- For env var PRs - description must say WHICH env var to add and WHERE
- For breaking-change PRs - description must say rollback plan
- For paid-API PRs - description must say credit-safety story
- For stacked PRs - description must say stacking order
- Missing structural section = surface as [HIGH][PR-Description]. Do NOT nit
  on grammar or prose style.

Project conventions: <paste>
PR description: <paste full body>
PR context: <paste>

Process as in generic prompt.
```

### Codex pass (parallel with subagents)

In parallel with the 6 Claude subagents, launch Codex from the worktree directory:

```bash
cd "$WORKTREE_DIR" && codex exec -m gpt-5.5 review --base <base-branch> --title "<PR title>" \
  2>&1 > /tmp/codex_pr<num>.txt &
```

`-m gpt-5.5` is the skill default - it overrides the global `~/.codex/config.toml` model setting. On truncation, retry once with `-m gpt-5.4` (see pitfall below).

Run in the background so the main agent isn't blocked waiting on Codex.

Codex prompt:
```
You are an independent senior reviewer providing a second opinion.

[INSERT HARD RULES BLOCK]

Review the diff at /tmp/pr<num>.diff. PR branch is checked out locally so you
can read actual files for line numbers.

PR context: <paste>
Project conventions: <paste>

Find what's wrong. Be adversarial. If section is clean, say so explicitly.

OUTPUT FORMAT (no chain-of-thought, no narration):

## Codex Review

### Findings
[SEVERITY][category] file:line - headline
What: <code snippet + explanation>
Why it matters: <impact>
Fix: <concrete change>

(continue for all findings)

### Verdict: <clean | N findings>
```

**Known pitfall**: The Codex CLI in non-interactive `codex exec` mode sometimes truncates mid-investigation. If output is truncated and does not contain a final "### Verdict:":
- Retry once with `-m gpt-5.4` (fallback model - different generation, often does not trigger the same truncation).
- If still truncated, skip the Codex pass and note in the output "Codex unavailable - 6-Claude convergence applied".
- Don't waste time on a third attempt; do not downgrade below 5.4 (mini truncates more often).

### Phase 1 → Phase 2 handoff

After Phase 1:
- `claude_findings` = union of the 6 subagent outputs (4 generic + Security + Deployment)
- `codex_findings` = Codex output (if completed)

Dedup within `claude_findings`: if 2+ agents flagged the same hole (same file, line ± 5, same conceptual issue), merge with a note "subagents: gen-1 + gen-3 + Sec". Convergence count = HIGH signal.

With 4 generic agents, a reliable convergence threshold is **2 of 4 = high signal**, **3+ of 4 = almost certain**.

## Phase 2 - Adversarial cross-review (parallel)

Launch 2 parallel Task calls:

### Call A: Claude reviews Codex findings

```
You are doing adversarial cross-review. Codex flagged findings below. For each:
- AGREE: real issue, Codex caught something valid
- DISAGREE: wrong because <reason> (code handles this, intentional design,
  conditions cannot occur, nitpick disguised as bug)
- NEEDS_CONTEXT: cannot tell without info not in diff. Explain what's missing.

Be honest. If Codex is right, say AGREE - don't defend Claude's blind spots.

[INSERT HARD RULES BLOCK]

Project conventions: <paste>
Diff: /tmp/pr<num>.diff
Codex findings to review: <paste>
```

### Call B: Codex reviews Claude findings

Same approach, mirrored prompt. Codex challenges Claude's findings.

**If Codex is unavailable** - Phase 2 is skipped; rely on intra-Claude convergence only.

## Phase 3 - Synthesis (main agent)

Artifacts:
1. `claude_findings` (6 agents, post-dedup)
2. `codex_findings`
3. `claude_on_codex` (cross-review verdicts)
4. `codex_on_claude` (cross-review verdicts)

Decision tree per finding:

| Source | Cross-review | Decision |
|---|---|---|
| Codex | Claude AGREE | Surface high-confidence |
| Codex | Claude DISAGREE | Drop (unless Critical → "Contested") |
| Codex | Claude NEEDS_CONTEXT | Surface in "Verify Manually" |
| Claude single agent | Codex AGREE | Surface high-confidence |
| Claude 2+ agents converged | (any) | Surface high-confidence |
| Claude single agent | Codex DISAGREE | Drop (unless Critical → "Contested") |
| Claude single agent | Codex unavailable | Surface only if Critical/HIGH or [INTENT-VERIFY] |

**[INTENT-VERIFY] findings ALWAYS surface** - silent behavior changes require author confirmation, not reviewer judgment.

**Contested Criticals are never dropped** - "⚠ Contested: <Disagreer> says <reason>" - the user resolves.

### Output format

```markdown
## Code Review - PR #N

**Verdict: <Ready to Merge | Needs Attention | Needs Work>**
<One sentence on what to do next.>

Reviewers: 6 Claude subagents (4 generic + Security + Deployment) + Codex.
Convergence: <X findings caught by 2+ agents, Y by 1 agent + Codex>.

---

## Must Fix (Critical / High)

**1. [SEVERITY][category] file:line - headline**

**What**: 2-4 sentences with the actual code snippet quoted (use ``` markdown block).
The reader should not need to open the file to grasp the issue. Explain the
contradiction, conditions, failure scenario.

**Why it matters**: 1-2 sentences. Real impact.

**Fix**: Concrete change. Code snippet if non-trivial.

_Caught by: <which agents converged>_

---

## Should Fix (Medium)

Shorter format: **headline + a one-or-two-line What + Fix**. "Why it matters" is omitted (at Medium impact it's usually obvious from the headline or What). Code snippet is omitted if the headline already named the location. Group by file when 3+ findings touch the same file.

```
**N. [MEDIUM][category] file:line - headline**

**What**: one or two lines. Concretely WHAT is wrong (not just "regex incomplete" - "regex misses `.rubocop.yml`, `.rspec`, `spec/`"). Not a full paragraph.

**Fix**: concrete change. Code snippet inline OK.

_Caught by: N/6._
```

Do NOT collapse Medium findings to headline-only - the reader should understand the issue without opening the file. "A couple of words of detail" means exactly one or two full lines in What, not an empty field. If there is nothing to say in What beyond the headline, the finding is probably Low, not Medium.

---

## Intent Verify (silent behavior changes)

- file:line - "<old> → <new>" not in PR description. Confirm intent.

---

## Contested

- Issue stated with both reviewers' positions. The user resolves.

---

## Verify Manually

- Single-source High items where the cross-reviewer answered NEEDS_CONTEXT.

---

## Clean (verified)

- TLS verification ✓
- API key from ENV ✓
- (etc - things confirmed clean to balance the negative findings)

---

## Stats

Pre-debate: <N> findings (Claude: X, Codex: Y). Post-debate: <surfaced>
surfaced + <contested> contested + <verify> verify. False positive cut: <%>.
```

### Verdict guidelines

- **Ready to Merge** - 0 Critical (including contested), 0 confirmed High; ≤2 Medium; nothing in Verify.
- **Needs Attention** - 1-2 confirmed High, or several Medium, or 1 contested Critical, or any [INTENT-VERIFY] present.
- **Needs Work** - any confirmed Critical, ≥3 confirmed High, a critical-path test gap, or a broken deploy procedure.

## Phase 4 - Offer to post

After the output:
```
Post as a PR comment via `gh pr review --comment <num> -F -`? (y/n)
```

If "y" - save to `/tmp/review_pr<num>.md` and run `gh pr review --comment <num> --repo <owner>/<repo> -F /tmp/review_pr<num>.md`. If "n" - leave the output in chat.

Do not post automatically without an explicit y/yes.

## Phase 5 - Cleanup

After Phase 4 (regardless of post or skip):
```bash
git worktree remove /tmp/pr<num>_worktree
```

The worktree is removed so they don't accumulate. Without cleanup, `git worktree list` grows and you eventually need `git worktree prune`.

If the worktree is busy (subagent still holds an fd), use `git worktree remove --force`.

## Hard rules

- **Phase 1 reviewers (6 Claude + Codex) are blind to each other.** Otherwise anchoring bias.
- **7 parallel Task/Bash calls in a single message.** Sequential = 7x slower.
- **CLAUDE.md + AGENTS.md in EVERY prompt.** Without them agents flag violations of conventions that don't exist.
- **HARD RULES BLOCK pasted into EVERY prompt** (location citations / finding format / intent verification / domain knowledge / cross-field consistency / skip list).
- **`git worktree add` before launching subagents** - so they can open files and use real line numbers, not diff positions. Worktree, not `gh pr checkout` - so parallel reviews of other PRs in the main working dir are not blocked.
- **Diff > 2000 lines** - warn the user and offer a split. The skill will still run but fidelity drops.
- **[INTENT-VERIFY] is never dropped at synthesis.**
- **Contested Criticals are never dropped at synthesis.**
- **Senior architect voice in output:** direct, no hedging ("might", "could potentially"), no preambles ("Great PR, just a few notes"), no emoji, no exclamation marks.
- **Do not post to GitHub without an explicit y/yes.**
- **Verdict strictly by the rules.** No sycophantic "looks great" if there is a confirmed Critical.
- **Cleanup worktree in Phase 5** - do not let them accumulate.

## What NOT to do

- Do not run subagents sequentially - parallel runs are the only way to get independent signal.
- Do not show subagent raw output. Only synthesized.
- Do not offer "add a TODO" / "add a comment" suggestions.
- Do not flag naming when a linter is configured in the repo.
- Do not propose stylistic rewrites if the code works.
- Do not produce one-sentence findings - they get lost and aren't actionable.
- Do not use diff hunk positions as line numbers.
- Do not run 5 specialized agents (Logic/Security/Tests/Perf/Deploy) - that is the legacy setup; generic broad-mandate agents find more cross-cutting issues. Current correct setup: 4 generic + 1 Security + 1 Deployment.
- Do not use `gh pr checkout` - it blocks parallel reviews of other PRs. Use `git worktree add` only.

## Pitfalls

**Codex CLI truncates mid-investigation** - a typical problem of `codex exec` non-interactive mode. Default `-m gpt-5.5`; fallback `-m gpt-5.4`. If both truncate, skip and note "Codex unavailable - 6-Claude convergence applied". Don't burn time on a 3rd attempt.

**Specialized agents miss cross-cutting issues** - e.g. "approval gate filter does not include the same fields the idempotency key uses". A Logic specialist looks at approval logic in isolation and doesn't compare with other files. Solution: 3 generic agents have a broad mandate and natural cross-reference, plus the CROSS-FIELD CONSISTENCY rule in HARD RULES BLOCK.

**Phase 2 reviewer always AGREEs** - sycophancy. If >70% of findings come back as AGREE, abort and tell the user "Phase 2 debate degenerate, don't trust it - verify manually".

**Line numbers - file vs diff** - subagents by default cite diff positions. This is a PR-killer mistake. The HARD RULE in every prompt + the worktree are mandatory.

**Stacked PR** - the base branch may not be master. Use `gh pr view ... --json baseRefName` - take the base from the API, not from assumption.

**Huge diff (>2000 lines)** - warn the user and offer a split: "Diff is large (X lines). Run the full review or scope by directory?".

**CLAUDE.md very long (>300 lines)** - extract only the relevant sections (severity rules, hard rules, codebase quirks). Don't dump everything into every prompt.

**Conflict between subagents in Phase 1** - Generic_1 says "race", Generic_2 says "fine". That's OK - both go into claude_findings, and Codex in Phase 2 will adjudicate.

**Codex strangely AGREES with nonsense in Phase 2** - tighten the skip-list in the Codex prompt: "Skip anything that isn't a confirmable bug. Style and 'consider X' are NOT in scope."

## Example invocation

**User:** "/claude-super-review 247"

**Claude:**
1. `gh pr view 247 --json title,body,files,headRefName,baseRefName,author`
2. `gh pr diff 247 > /tmp/pr247.diff`
3. `BRANCH=$(gh pr view 247 --json headRefName -q .headRefName); git fetch origin "$BRANCH"; git worktree add /tmp/pr247_worktree "origin/$BRANCH"` (CRITICAL - isolated worktree preserves parallelism)
4. Read `CLAUDE.md` + `AGENTS.md` in the worktree root.
5. **Phase 1**: spawn 6 subagents (4 generic + Security + Deployment) + Codex in parallel - all blind to each other. Each prompt includes HARD RULES BLOCK, project conventions, PR context, and worktree path.
6. Wait for all 6 + Codex (background notifications). Dedup intra-Claude (4 generic agents give a good convergence signal).
7. **Phase 2**: parallel calls - Claude reviews Codex findings, Codex reviews Claude findings.
8. **Phase 3**: synthesize per the decision tree → final markdown with detailed findings.
9. **Phase 4**: ask "Post as a PR comment? (y/n)".
10. If "y" - `gh pr review --comment 247 --repo <owner>/<repo> -F /tmp/review_pr247.md`.
11. **Phase 5**: `git worktree remove /tmp/pr247_worktree`.

## Postmortem hook (after each review)

After the user has posted the review or added a PR comment - check:
- Which findings did THEY add that the skill did not catch? (these are gaps)
- Which findings did the skill produce that they did not use? (this is noise)
- If a pattern repeats (the skill misses a specific class of bugs) - propose a skill update.

Currently known gaps (encoded in HARD RULES BLOCK):
- Cross-field consistency (approval filters by X but idempotency by Y) - solved by generic agents + the CROSS-FIELD CONSISTENCY block.
- Silent behavior changes (validity 30d→24h) - solved by the [INTENT-VERIFY] category.
- Domain API limits (Apollo 50k cap) - solved by the DOMAIN KNOWLEDGE block.
- Diff line vs file line - solved by the LOCATION CITATIONS block + worktree.
- Block-list regex with holes (refresh_token / bearer / private_key not covered) - solved by the Sensitivity-of-redaction analysis in the Security subagent prompt.
