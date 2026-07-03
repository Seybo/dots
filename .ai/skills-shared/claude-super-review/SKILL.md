---
name: claude-super-review
description: Multi-agent code review for PR / branch / diff in any repo. Runs 6 parallel Claude subagents (4 generic adversarial + 1 Security + 1 Deployment) + an independent Codex pass. Convergence filter (≥2 agents confirmed = valid issue; Critical/HIGH = always surfaced). Surface Critical / High / Medium with mandatory short writeup "what's wrong / code / why it matters / fix". Senior architect voice, output ready to paste into a GitHub comment. Use this skill whenever the user writes "/claude-super-review", "review PR 247", "review my branch", "look at what X pushed", supplies a GitHub PR URL, or asks for a code review of uncommitted changes. Trigger even if "skill" isn't said explicitly - this is the default review workflow.
---

# code-review

Multi-agent code review skill - runs 6 parallel Claude subagents (a mixed Opus+Sonnet panel, with the model set EXPLICITLY in each Task call) and a Codex pass on the same diff, filters via convergence, returns a ranked list with verdict. Optimized for AI-generated code where single-pass review misses blind spots, and for cross-cutting issues that narrow specialists skip over.

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
     (2x model: "opus" + 2x model: "sonnet")
   - 1 Security subagent → secrets / PII / injection / regex completeness (model: "opus")
   - 1 Deployment subagent → migrations / env vars / PR description structure (model: "sonnet")
   - 1 Codex independent pass → cross-vendor signal (gpt-5.5)

PHASE 2 - Adversarial cross-review (parallel):
   - Claude reviews each codex_finding: AGREE / DISAGREE / NEEDS_CONTEXT
   - Codex reviews each claude_finding (post-convergence): AGREE / DISAGREE / NEEDS_CONTEXT

PHASE 3 - Synthesis (main agent):
   - 2+ agents flagged the same issue → surface high-confidence
   - 1 agent flagged Critical/HIGH → surface
   - 1 agent flagged Medium → drop unless interesting
   - Intent-verification findings always surface

PHASE 3.5 - Save report: ALWAYS write the full Phase 3 markdown to a `super-review.md` file (task folder if known, else fallback). Print the path.
PHASE 4 - Interactive posting: ask which findings to post, leave each as a PENDING inline comment (Variant A format), never submit
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

### Model assignment (MANDATORY)

Pass `model` explicitly in EVERY Task call. Without an explicit `model`, the subagent inherits the main session's model - which can be 2-3x more expensive (e.g. Fable 5 at $10/$50 per MTok vs Opus 4.8 at $5/$25 and Sonnet 4.6 at $3/$15), and the review cost becomes uncontrolled.

| Role | model | Why |
|---|---|---|
| Generic 1, Generic 2 | `"opus"` (= Opus 4.8) | Deep cross-file reasoning; Opus 4.8 has a stated gain specifically in bug-finding |
| Generic 3, Generic 4 | `"sonnet"` (= Sonnet 4.6) | Strong code reviewer; a second model in the panel gives cross-model diversity in convergence |
| Security | `"opus"` | The most expensive class of misses; adversarial analysis of regex/auth/race needs maximum depth |
| Deployment | `"sonnet"` | The most structural role (migrations / env vars / PR description) - the prompt does the heavy lifting |
| Phase 2 Call A (Claude reviews Codex) | `"opus"` | Adjudication: the power to kill findings - a wrong DISAGREE costs more than the tokens saved |
| Codex | `gpt-5.5` (CLI `-m`) | Cross-vendor diversity; fallback `gpt-5.4` |

The layout is locked by Sasha 2026-06-09 - do not change it without his decision.

Do NOT use Haiku in any role: the loss of depth on subtle bugs destroys the pipeline's value, plus the 200K context may not fit a large PR + files.

Logic of the mixed panel: Opus sits where maximum depth is needed (2 generic + Security + adjudication), Sonnet where the prompt does the heavy lifting (Deployment) and where a second model adds diversity (2 generic). Two identical models share common blind spots, so Opus+Sonnet convergence is a stronger signal than two runs of one model; the same principle as the cross-vendor signal from Codex.

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

SELF-CORROBORATING DIFF - HARD RULE (the oracle moved with the code):
A diff can be internally consistent and still wrong. When the SAME change edits
both a behavior AND the thing that would otherwise prove it wrong, that thing
stops being evidence. Passing specs, a matching comment, a green fixture prove
NOTHING when they were rewritten in the same diff to agree with the new code.
Watch for these paired edits and treat the "confirming" side as suspect, not
as proof:
- Code changed AND its test/fixture/expected-output/snapshot changed together
  -> a green suite only proves the test now matches the code, not that either
  is correct. The specs were moved to bless the behavior.
- Code changed AND the comment / docstring / doc that describes it changed
  together -> the comment corroborates the code because the same author wrote
  both from the same assumption; it is not independent confirmation.
- A constant / threshold / enum changed AND the assertion checking it changed.
- A parser/validator NARROWED (fields dropped, a branch removed, a nil
  hardcoded) AND the sample input it reads edited to no longer contain the
  dropped data.
The rule: when behavior and its oracle move in the same direction in one diff,
you MUST find an oracle OUTSIDE the diff before trusting it. Options, best
first:
0. THE TASK / PR DESCRIPTION + AC YOU WERE ALREADY GIVEN. Check this FIRST -
   it is free and already in your prompt (Step 2 passes it to every reviewer).
   Does the change contradict a stated design decision, requirement, or
   acceptance criterion? Silent removal of an AC-required behavior, or code
   that does the OPPOSITE of what the description says, is a finding on its own
   - you do not need any external system to confirm it. Also surface it as
   [INTENT-VERIFY]. Most self-corroborating diffs are caught here, without ever
   leaving the prompt.
1. The vendor's real API output / official docs (never a fixture as proof of an
   external shape - a fixture is an assumption, and a sanitized/redacted sample
   is NEVER the real shape).
2. An independent existing caller / consumer that the diff did NOT touch.
3. The pre-diff version in git history - does the change DELETE data or a code
   path the rest of the system still relies on?
If the only thing vouching for a change is something the same change edited,
flag it:
  [HIGH][unverified-by-construction] file:line - behavior X and its <test/
  fixture/comment> were changed together; correctness is unconfirmed because
  nothing outside this diff vouches for it. Verify <field/value> against
  <AC item / external source>.
This is the class that defeats convergence AND a green suite: every automated
signal comes back green because the check was edited to pass. (Real miss: a
People Search parser was rewritten to hardcode company identity to nil on the
premise "the API returns no org id/domain," and the SAME diff edited the
fixture to strip `organization.id`/`primary_domain` - so specs passed, lint
passed, comment agreed, and every prospect silently landed unrouted. TWO
oracles would have caught it: (0) the task said People Search store is "the
only place campaign_organization_id gets set" and the AC required a G3 counter
- the diff removed BOTH, contradicting the description already in the prompt;
(1) the real Apollo API does return those org fields - the sample the author
trusted was a sanitized probe. The cheap catch was (0), and it needed nothing
but reading the AC.)

PRECONDITION & SEVERITY DISCIPLINE - HARD RULE:
For ANY finding that depends on control flow, exception handling, or a state
machine ("the error is swallowed", "the call is left in state X", "this masks
the real error", "X is lost"):
1. Trace the NORMAL path first, then state the EXACT trigger in one line:
   "Triggers only when: <condition>." If it needs a SECOND simultaneous failure
   (a compound failure - e.g. the error-recording write ITSELF raises), say so.
2. Severity = likelihood(precondition) x impact, NOT impact alone. A real bug
   gated behind a rare/compound precondition is at most Medium, NOT High.
3. Verify language semantics before naming a consequence. Do NOT write
   "lost"/"swallowed"/"never"/"silently" unless confirmed. (Ruby: raising inside
   a `rescue` auto-sets the new exception's `.cause` to the original - so it is
   NOT lost, only possibly not surfaced by the error formatter. Also check
   ensure-blocks, retry order, transaction/rollback order.) Use precise wording
   like "not surfaced to the operator (preserved as `.cause`)".
If you cannot state the precondition crisply in one line, you have NOT verified
it - downgrade or move to "Verify Manually"; do not flag it High.

COVERAGE OVER SELF-CENSORSHIP:
Report every issue you find, including ones you are uncertain about - mark
those [confidence: low]. Do NOT silently drop a finding because you doubt its
importance: convergence and adversarial cross-review filter downstream, and a
finding dropped at the source is unrecoverable. (The SKIP LIST below excludes
noise classes, not uncertain bugs. PRECONDITION discipline still applies:
state the trigger honestly and downgrade severity, but keep the finding.)

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
# Write the Codex prompt (below) to a file first, then run PLAIN `codex exec` with it.
# DO NOT use `codex exec review --base <BRANCH> "<prompt>"`: the CLI rejects a custom
# [PROMPT] together with --base ("the argument '--base <BRANCH>' cannot be used with
# '[PROMPT]'") - confirmed on codex 0.133 AND 0.136, by-design, not a version bug.
# Plain `codex exec` has no such restriction and preserves the skill's HARD RULES prompt.
cd "$WORKTREE_DIR" && codex exec -m gpt-5.5 "$(cat /tmp/codex_prompt_pr<num>.txt)" \
  > /tmp/codex_pr<num>.txt 2>&1 &
```

`-m gpt-5.5` is the skill default - it overrides the global `~/.codex/config.toml` model setting. On truncation, retry once with `-m gpt-5.4` (see pitfall below).

The prompt already tells Codex to read `/tmp/pr<num>.diff` and open files in the checked-out worktree for real line numbers, so the plain `codex exec` form has everything it needs.

(Git-aware alternative WITHOUT a custom prompt: `cd "$WORKTREE_DIR" && codex exec -m gpt-5.5 review --base <base-branch> > /tmp/codex_pr<num>.txt 2>&1 &` - uses Codex's built-in review against the base, but you lose the HARD RULES / output format. Prefer the plain-exec form above. Note: `review` has no `--title` flag.)

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

**Pitfall `--base` + custom prompt**: `codex exec review --base <BRANCH>` does NOT accept a custom `[PROMPT]` (CLI error: "the argument '--base <BRANCH>' cannot be used with '[PROMPT]'"; true on 0.133-0.136, by-design). Always pass the skill prompt via plain `codex exec -m <model> "<prompt>"` (the prompt references `/tmp/pr<num>.diff` + the worktree). Reserve `review --base <BRANCH>` for a no-custom-prompt git-aware pass only. `review` also has no `--title` flag. If you see this arg-error in Codex output, it is NOT truncation and NOT a reason to update codex - just switch to the plain `codex exec` form.

### Phase 1 → Phase 2 handoff

After Phase 1:
- `claude_findings` = union of the 6 subagent outputs (4 generic + Security + Deployment)
- `codex_findings` = Codex output (if completed)

Dedup within `claude_findings`: if 2+ agents flagged the same hole (same file, line ± 5, same conceptual issue), merge with a note "subagents: gen-1 + gen-3 + Sec". Convergence count = HIGH signal.

With 4 generic agents, a reliable convergence threshold is **2 of 4 = high signal**, **3+ of 4 = almost certain**. Cross-model convergence (Opus+Sonnet within the panel, Claude+Codex across vendors) weighs more than agreement between two agents of the same model: different models don't share blind spots.

**BUT: convergence is NOT verification for control-flow / exception-semantics / state-machine claims.** N agents (and Codex) can AGREE on a plausible-but-overstated mechanism while sharing ONE blind spot (none traced the language semantics or the trigger precondition). Before surfacing such a finding as High, independently trace the normal path and state the exact precondition (see PRECONDITION & SEVERITY DISCIPLINE). Agreement on a mechanism is not proof it fires. (Real miss: a compound-edge "error masking" was tagged HIGH + "lost" even though Ruby preserves the original in `.cause` and the case needs a second simultaneous DB failure.)

## Phase 2 - Adversarial cross-review (parallel)

Launch 2 parallel Task calls:

### Call A: Claude reviews Codex findings

Task call with `model: "opus"` - adjudication decides the fate of findings, don't economize here.

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

## Phase 3.5 - Save the report to a file (ALWAYS, automatic)

After printing the Phase 3 markdown, ALWAYS persist the SAME markdown verbatim to a `super-review.md` file. This is not optional and needs no user prompt - the file is the durable artifact; the chat output scrolls away. Write it BEFORE Phase 4 (posting), so the report survives even if the user skips posting.

**Where to write it** (first match wins):

1. **Task folder known** - the invocation references a task under `/Volumes/dev/_tasks/<project>/<id>/` (the user passed a `task.md` path, a task folder path, or you derived one from the branch's Shortcut id). Write to `<task-folder>/super-review.md`.
2. **PR review, no task folder** - write to `<repo-root>/super-review.md` in the user's main working dir (NOT the throwaway worktree - it gets removed in Phase 5). If that would clobber an existing unrelated file, use `super-review-pr<num>.md`.
3. **Branch / staged / last-commit review, no task folder** - write to `<repo-root>/super-review.md`.

If a `super-review.md` already exists at the target from a previous run on the SAME scope, overwrite it (the latest review wins). If it exists but covers a DIFFERENT scope, suffix the new one (`super-review-<branch-or-pr>.md`) rather than clobbering.

Use the Write tool, not a shell heredoc. After writing, print one line: `Report saved: <absolute path>`.

The on-disk file is the EXACT Phase 3 output (same headline, ranked findings, Clean section, Stats) - do not summarize or trim it for the file. The interactive shortening rules in Phase 4 apply ONLY to posted PR comments, never to this file.

## Phase 4 - Interactive posting (pending review, NEVER submit)

Do NOT change the review output (Phase 3) - Sasha likes the full ranked format. The interactivity is only at the posting stage.

1. After the review output, ask which findings to leave pending comments on (by their number in the report):
   `Which findings should I leave as pending PR comments? (e.g. "1, 4" / "all High" / "none for now")`
2. For EACH selected finding, leave an inline **pending** comment anchored to the exact line. Not selected - don't comment.
3. NEVER submit without an explicit "submit/send". Pending is the default: Sasha clicks Submit/Discard in GitHub himself.

**STOP before posting:** run the `PRE-POST GATE` on EVERY drafted comment (defined below, right before `## Phase 5`). Do NOT assemble `payload.json` until all 4 gate items pass. This is not optional - this is exactly where comments bloat.

**Pending mechanic** (NOT `gh pr review --comment` - that submits immediately): create the review via REST WITHOUT the `event` field:
```bash
HEAD=$(gh pr view <num> --repo <owner>/<repo> --json headRefOid -q .headRefOid)
jq -n --arg body "$(cat /tmp/cmt.md)" --arg c "$HEAD" \
  '{commit_id:$c, comments:[{path:"<file>", line:<N>, side:"RIGHT", body:$body}]}' > /tmp/payload.json
gh api -X POST /repos/<owner>/<repo>/pulls/<num>/reviews --input /tmp/payload.json --jq '{id,state,html_url}'
# state == PENDING is required. Multiple findings -> multiple objects in comments[] in ONE POST (one pending review, don't multiply).
```
- A single line is more reliable: send only `line` + `side:"RIGHT"`. `start_line`+`line` via this endpoint often loses the range (the anchor collapses onto the end line).
- You can only anchor to lines inside the diff hunk. Write the comment body to a file (`jq --arg`) - less escaping pain.
- **Body-level / top-level comment** (not anchored to a line: about the PR description, a general point): GitHub's Submit-review dialog opens the summary box EMPTY and does NOT load the API-set `body` → the summary is DROPPED on submit (confirmed on PR#39). So for ANY non-inline comment, ALWAYS hand Sasha the ready-to-paste text and explicitly say "add this as a top-level comment by hand". Never rely on the review `body` reaching the PR via the UI.

**Comment format (LOCKED - "Variant A", Sasha's senior style. Standard approved on PR#40):**

**TOP PRINCIPLE: as short as possible.** Write the minimum a senior needs to grasp it and act without opening the file. Cut every word that isn't load-bearing. Length is dictated ONLY by the finding's genuine complexity, never by a target number. There is NO fixed limit (the ~56 words on PR#40 was an observation, NOT a bar): don't pad to look thorough, and don't mechanically trim to hit some number. A simple finding is two lines; a complex mechanism that can't be explained shorter is exactly as long as each clause genuinely needs.

Default structure = **THREE short blocks, separated by a BLANK LINE.** Goal: the comment scans at a glance instead of reading like a wall of text.

1. **Bold takeaway in one sentence: WHAT breaks** (impact, not mechanism).
2. One line, `problem -> consequence`, with `file:line` and identifiers in backticks. One link, not a list.
3. A short, direct ask/question.

Hard rules (a violation means rewrite):
- **Blank lines between blocks are MANDATORY, each block = 1 line.** A dense 3-5 sentence paragraph with no breaks is WRONG, even if correct on substance. If you catch yourself writing a wall of text, split into 3 blocks and drop the filler. (This is the new rule: the skill used to say cram into 1-2 lines as one paragraph - that produced an unreadable block, so we do NOT do that anymore.)
- **Simple English, like a Senior Tech Engineer.** Short words, active voice. NOT academic vocab: "comes back empty" not "resolves to missing"; "stored as if verified" not "stored as first-class"; "response shape" not "envelope"; "won't be retried" not "suppressed from re-selection"; "stuck" not "wedged".
- NO severity tags (`[HIGH]`, `[category]`) and NO `What/Why/Fix` headers.
- **Length is dictated by complexity, not a target number (see TOP PRINCIPLE). Default to the shortest version that's still clear.** The block structure never changes:
  - simple finding → 2 blocks (bold takeaway + question), middle can be dropped.
  - normal → 3 blocks as above.
  - genuinely complex mechanism → add ONLY the detail you can't omit (an extra fact in the middle block, an important caveat in the question's parenthetical) - that is the only thing that justifies length. Every clause earns its place; the block stays 1-2 lines, not a paragraph.
  - do NOT trim a needed explanation to hit a number, and do NOT pad to look thorough - both are wrong.
- For a concrete fix, put a GitHub suggestion block as a separate block AFTER the question. English (GitHub-visible). Don't add AI attribution.

Examples = **THE FORMAT STANDARD. Copy the STRUCTURE (3 blocks, blank lines, plain words), not the text.** All three approved by Sasha on PR#40:

Normal finding (3 blocks):
> **A People Search rerun overwrites the enriched `full_name` with the old search value.**
>
> `last_name` is protected by `preserved_last_name`, `full_name` is not -> after Enrich sets `"Eric Example"`, a rerun drops it back to `"Eric"` while `last_name` stays `"Example"`.
>
> Add a `preserved_full_name` the same way?

With a suggestion block (the fix goes AFTER the question, as its own block):
> **Passing `api:` skips the approval gate, so a live run can spend credits with no `--approve-live-call`.**
>
> The gate checks `api.nil?` instead of `live`. The CLI is safe (never passes `api:`), but a direct `Run.call(api: ...)` reserves and calls `bulk_match` ungated.
>
> Gate on `live` and pass `approve_first_live_call: true` in the specs?
>
> ` ``suggestion ` (GitHub suggestion block with the ready replacement line)

Complex mechanism (middle block a bit denser, but the structure and blank lines hold):
> **If the live response does not echo our `id`, the whole batch comes back as `missing` after a paid call.**
>
> Apollo prospects only match by `id` here, no fallback by design. A wrong response shape means `credits_consumed > 0` but every row gets `email_status: 'missing'` and an `enrichment_date` - so no error, and no retry for 30 days.
>
> Raise when `credits_consumed > 0` but `matched == 0`, so a shape mismatch fails loud?

---

**PRE-POST GATE (run before EVERY `gh api POST`, binary: failing ANY item = rewrite BEFORE posting).**

This fixes the recurring "comments bloat" drift - Sasha caught it 3 times in a row because the advisory "shorter" rule above does NOT fire. This is a hard checklist, not advice. Run every drafted comment through the 4 items:

1. **Middle block = EXACTLY one sentence** (one `problem -> consequence` link). Two sentences = cut to one. Keep a second fact ONLY when the finding can't be understood without it (the "complex mechanism" class), and then it lives in a parenthetical, not a separate sentence.
2. **EXACTLY one question/ask in the final block.** Constructions like "X, or Y?", "confirm X and decide Y", "..., not Z?" are a double ask: collapse to one.
3. **Zero meta-explanations of "how it reads".** Delete perception phrases: "reads as cleanup", "so it looks like", "feels like", "comes across as", "looks like". A comment says WHAT breaks and what it threatens, not how the reader sees it. This is my main source of extra weight - cut it first.
4. **Literal size-diff against the standard.** Put your comment mentally next to the matching PR#40 example (normal / suggestion / complex mechanism). Visibly longer than the standard for its class = cut to its size. The standard is the CEILING for the finding's class, not the floor.

Only after all 4 pass on ALL comments - assemble `payload.json` and post. If you catch yourself thinking "but this needs context" - that's almost always item 3 (explaining framing). Context goes in the Phase 3 ranked output, not the inline comment.

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
- **`model` explicit in EVERY Task call** (gen-1/gen-2 + Security = `"opus"`, gen-3/gen-4 + Deployment = `"sonnet"`, Phase 2 Call A = `"opus"`). Inheriting the session model is forbidden - the session may be running on an expensive model, and the review silently costs 2-3x more.
- **CLAUDE.md + AGENTS.md in EVERY prompt.** Without them agents flag violations of conventions that don't exist.
- **HARD RULES BLOCK pasted into EVERY prompt** (location citations / finding format / intent verification / domain knowledge / cross-field consistency / skip list).
- **`git worktree add` before launching subagents** - so they can open files and use real line numbers, not diff positions. Worktree, not `gh pr checkout` - so parallel reviews of other PRs in the main working dir are not blocked.
- **Diff > 2000 lines** - warn the user and offer a split. The skill will still run but fidelity drops.
- **[INTENT-VERIFY] is never dropped at synthesis.**
- **Contested Criticals are never dropped at synthesis.**
- **Always save the Phase 3 report to `super-review.md` (Phase 3.5)** before posting - task folder if known, else repo root. Write it verbatim, no prompt, print the path.
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
5. **Phase 1**: spawn 6 subagents (4 generic + Security + Deployment) + Codex in parallel - all blind to each other. Models: gen-1/gen-2 + Security `model: "opus"`, gen-3/gen-4 + Deployment `model: "sonnet"`. Each prompt includes HARD RULES BLOCK, project conventions, PR context, and worktree path.
6. Wait for all 6 + Codex (background notifications). Dedup intra-Claude (4 generic agents give a good convergence signal).
7. **Phase 2**: parallel calls - Claude reviews Codex findings, Codex reviews Claude findings.
8. **Phase 3**: synthesize per the decision tree → final markdown with detailed findings.
8.5. **Phase 3.5**: write the same markdown verbatim to `super-review.md` (task folder if known, else repo root). Print `Report saved: <path>`.
9. **Phase 4**: ask "which findings to leave as pending PR comments?" (by their number in the report).
10. For the selected ones - inline pending comments ("Variant A": takeaway in bold on the first line, no `[HIGH]` tags) via `gh api -X POST .../pulls/247/reviews` WITHOUT `event`; never submit (Sasha clicks Submit/Discard).
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
- Severity inflation / overstated exception-flow claims (a compound-edge tagged HIGH + "lost" without verifying the precondition or language semantics) - solved by the PRECONDITION & SEVERITY DISCIPLINE rule + the "convergence is not verification" note in synthesis.
