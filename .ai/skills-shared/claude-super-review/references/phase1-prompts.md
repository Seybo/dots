# Phase 1 — model assignment, subagent prompts, Codex pass

Read this file when composing Phase 1. Every prompt below gets the full HARD RULES BLOCK from `references/hard-rules.md` pasted where marked.

## Model assignment (MANDATORY)

Pass `model` explicitly in EVERY Task call. Without an explicit `model`, the subagent inherits the main session's model - which can be 2-3x more expensive (e.g. Fable 5 at $10/$50 per MTok vs Opus 4.8 at $5/$25 and Sonnet 4.6 at $3/$15), and the review cost becomes uncontrolled.

| Role | model | Why |
|---|---|---|
| Generic 1, Generic 2 | `"opus"` (= Opus 4.8) | Deep cross-file reasoning; Opus 4.8 has a stated gain specifically in bug-finding |
| Generic 3 | `"sonnet"` (= Sonnet 4.6) | Strong code reviewer; a second model in the panel gives cross-model diversity in convergence |
| Architecture | `"sonnet"` (= Sonnet 4.6) | Structural role for file/module split, God files, and layering; prompt does the heavy lifting while keeping the Sonnet share of the panel |
| Security | `"opus"` | The most expensive class of misses; adversarial analysis of regex/auth/race needs maximum depth |
| Deployment | `"sonnet"` | The most structural role (migrations / env vars / PR description) - the prompt does the heavy lifting |
| Phase 2 Call A (Claude reviews Codex) | `"opus"` | Adjudication: the power to kill findings - a wrong DISAGREE costs more than the tokens saved |
| Codex | `gpt-5.6-sol` (CLI `-m`, reasoning effort `high`) | Cross-vendor diversity; fallback `gpt-5.4` at `high` |

The layout is locked by Sasha 2026-06-09; Architecture role added 2026-07-10 by replacing one generic reviewer while preserving the Sonnet slot. Do not change it without his decision.

Do NOT use Haiku in any role: the loss of depth on subtle bugs destroys the pipeline's value, plus the 200K context may not fit a large PR + files.

Logic of the mixed panel: Opus sits where maximum depth is needed (2 generic + Security + adjudication), Sonnet where the prompt does the heavy lifting (Architecture + Deployment) and where a second model adds diversity (1 generic). Two identical models share common blind spots, so Opus+Sonnet convergence is a stronger signal than two runs of one model; the same principle as the cross-vendor signal from Codex.

## Subagents 1-3: Generic adversarial reviewers

Identical prompt for all three (this is intentional - same prompt, 3 separate runs, gives 3 independent signal sources):

```
You are a senior code reviewer. You have full mandate to find what is wrong
with this PR. No specific lens, no narrow focus - just find what's broken,
unsafe, or contradictory.

[INSERT HARD RULES BLOCK - see references/hard-rules.md]

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

## Subagent 4: Architecture + modularity

Model `"sonnet"`. This role keeps the PR from shipping one giant blob when it should be a directory of focused modules.

```
You are a senior software architect. Review this PR for STRUCTURE, not correctness - the other reviewers hunt bugs. Your single question: is the code at the right altitude, or is it being dumped into one oversized file/blob when it should be split across files, models, and modules in a clean architecture?

[INSERT HARD RULES BLOCK]

SCOPE OVERRIDE: the generic SKIP LIST's "could be extracted to a helper" exclusion does NOT bind you for genuinely large or multi-concern units - layout is your entire mandate. But keep your bar HIGH: flag material structural problems, never cosmetic ones. A 40-line function is fine; a 900-line file doing six unrelated jobs is not. Only judge code CHANGED or ADDED by THIS PR - do not flag a pre-existing God file the diff didn't create or materially grow.

What to flag, worst first:
- GOD FILE: a file added or grown large that mixes many concerns (types + IO + business logic + rendering + CLI wiring in one). Rule of thumb: a source file pushed past ~400-500 lines with more than one clear responsibility should be a directory of focused modules. Name each concern and where it should live.
- GOD FUNCTION / GOD CLASS: one function/class doing too much (long body, many responsibilities, deep nesting, dozens of methods). Name the split seams.
- CONCERNS NOT SEPARATED: pure logic tangled with IO / network / filesystem / rendering, so none of it is unit-testable in isolation; business rules that belong in a model sitting inline in a CLI command or controller.
- WRONG LAYER / WRONG DIRECTORY: code added to a file that does not match the project's own layout - read the module-layout / package-structure section of CLAUDE.md + AGENTS.md and hold the diff to it.
- DUPLICATION THAT WANTS A MODULE: the same block copy-pasted across 3+ files that should be one shared module.
- MISSING EXTENSION SEAM: variant-specific behavior added via a `switch (name)` / long if-else dispatcher in a shared module instead of a polymorphic seam, when the project documents such a convention. Do not invent a convention the repo lacks.

For EACH finding give a concrete TARGET ARCHITECTURE, not just "split this up" - show the file/module breakdown so the author can act. Match the target to the project's existing conventions; never impose a generic structure the repo does not use. If CLAUDE.md / AGENTS.md documents a layout, your proposed split MUST follow and cite it.

SEVERITY:
- An oversized multi-concern file / God-object INTRODUCED by this PR that will be a lasting maintenance and review blind spot -> [HIGH].
- A file trending too large, a function that should be 2-3, a misplaced module -> [MEDIUM].
- Do NOT flag small single-purpose files, short functions, or preference-level reshuffles. If the only argument is "I'd organize it differently", drop it.

Project conventions: <paste module-layout / package-structure sections>
PR context: <paste>

Process as in the generic prompt. Find what is structurally wrong. If the layout is already clean, say so explicitly. End with "Verdict: <clean | N findings>".
```

## Subagent 5: Security focus

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

## Subagent 6: Deployment + PR-description structure

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

## Codex pass (parallel with subagents)

In parallel with the 6 Claude subagents, launch Codex from the worktree directory:

```bash
# Write the Codex prompt (below) to a file first, then run PLAIN `codex exec` with it.
# DO NOT use `codex exec review --base <BRANCH> "<prompt>"`: the CLI rejects a custom
# [PROMPT] together with --base ("the argument '--base <BRANCH>' cannot be used with
# '[PROMPT]'") - confirmed on codex 0.133 AND 0.136, by-design, not a version bug.
# Plain `codex exec` has no such restriction and preserves the skill's HARD RULES prompt.
cd "$WORKTREE_DIR" && codex exec -m gpt-5.6-sol -c 'model_reasoning_effort="high"' "$(cat /tmp/codex_prompt_pr<num>.txt)" \
  > /tmp/codex_pr<num>.txt 2>&1 &
```

`-m gpt-5.6-sol` with `-c 'model_reasoning_effort="high"'` is the skill default - it overrides the global `~/.codex/config.toml` model and reasoning-effort settings. On truncation, retry once with `-m gpt-5.4` at the same reasoning effort (see pitfalls below).

The prompt already tells Codex to read `/tmp/pr<num>.diff` and open files in the checked-out worktree for real line numbers, so the plain `codex exec` form has everything it needs.

(Git-aware alternative WITHOUT a custom prompt: `cd "$WORKTREE_DIR" && codex exec -m gpt-5.6-sol -c 'model_reasoning_effort="high"' review --base <base-branch> > /tmp/codex_pr<num>.txt 2>&1 &` - uses Codex's built-in review against the base, but you lose the HARD RULES / output format. Prefer the plain-exec form above. Note: `review` has no `--title` flag.)

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

## Codex pitfalls

**Codex CLI truncates mid-investigation** - a typical problem of `codex exec` non-interactive mode. If output is truncated and does not contain a final "### Verdict:":
- Retry once with `-m gpt-5.4 -c 'model_reasoning_effort="high"'` (fallback model - different generation, often does not trigger the same truncation).
- If still truncated, skip the Codex pass and note in the output "Codex unavailable - 6-Claude convergence applied".
- Don't waste time on a third attempt; do not downgrade below 5.4 (mini truncates more often).

**Pitfall `--base` + custom prompt**: `codex exec review --base <BRANCH>` does NOT accept a custom `[PROMPT]` (CLI error: "the argument '--base <BRANCH>' cannot be used with '[PROMPT]'"; true on 0.133-0.136, by-design). Always pass the skill prompt via plain `codex exec -m <model> "<prompt>"` (the prompt references `/tmp/pr<num>.diff` + the worktree). Reserve `review --base <BRANCH>` for a no-custom-prompt git-aware pass only. `review` also has no `--title` flag. If you see this arg-error in Codex output, it is NOT truncation and NOT a reason to update codex - just switch to the plain `codex exec` form.

**Codex strangely AGREES with nonsense in Phase 2** - tighten the skip-list in the Codex prompt: "Skip anything that isn't a confirmable bug. Style and 'consider X' are NOT in scope."
