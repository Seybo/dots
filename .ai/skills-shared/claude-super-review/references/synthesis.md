# Phases 1→2→3 — handoff, cross-review, synthesis, output format

Read this file when Phase 1 reviewers start returning.

## Phase 1 → Phase 2 handoff

After Phase 1:
- `claude_findings` = union of the 6 subagent outputs (3 generic + Architecture + Security + Deployment)
- `codex_findings` = Codex output (if completed)

Dedup within `claude_findings`: if 2+ agents flagged the same hole (same file, line ± 5, same conceptual issue), merge with a note "subagents: gen-1 + gen-3 + Sec". Convergence count = HIGH signal.

With 3 generic agents, a reliable generic convergence threshold is **2 of 3 = high signal**, **3 of 3 = almost certain**. Cross-model convergence (Opus+Sonnet within the panel, Claude+Codex across vendors) weighs more than agreement between two agents of the same model: different models don't share blind spots.

**Specialists (Architecture / Security / Deployment) rarely converge with generic agents** because their mandates include structural, security, and deployment classes that generic agents often skip. Judge specialist findings on substance, not only confirmation count: specialist High surfaces by itself, and concrete, well-justified specialist Medium findings (for example, Architecture identifies a real God file and target layout) count as "interesting" and are not automatically dropped as single-agent Mediums.

**BUT: convergence is NOT verification for control-flow / exception-semantics / state-machine claims.** N agents (and Codex) can AGREE on a plausible-but-overstated mechanism while sharing ONE blind spot (none traced the language semantics or the trigger precondition). Before surfacing such a finding as High, independently trace the normal path and state the exact precondition (see PRECONDITION & SEVERITY DISCIPLINE in `references/hard-rules.md`). Agreement on a mechanism is not proof it fires. (Real miss: a compound-edge "error masking" was tagged HIGH + "lost" even though Ruby preserves the original in `.cause` and the case needs a second simultaneous DB failure.)

**Conflict between subagents in Phase 1** - Generic_1 says "race", Generic_2 says "fine". That's OK - both go into claude_findings, and Codex in Phase 2 will adjudicate.

## Phase 2 - Adversarial cross-review (parallel)

When Codex completed, launch 2 parallel cross-review calls. If Codex was skipped or unavailable, skip Phase 2 and rely on intra-Claude convergence only.

### Call A: Claude reviews Codex findings

Task call with `model: "opus"` - adjudication decides the fate of findings, don't economize here.

```
You are doing adversarial cross-review. Codex flagged findings below. For each:
- AGREE: real issue, Codex caught something valid
- DISAGREE: wrong because <reason> (code handles this, intentional design,
  conditions cannot occur, nitpick disguised as bug)
- NEEDS_CONTEXT: cannot tell without info not in diff. Explain what's missing.

Be honest. If Codex is right, say AGREE - don't defend Claude's blind spots.

[INSERT HARD RULES BLOCK - see references/hard-rules.md]

Project conventions: <paste>
Diff: /tmp/pr<num>.diff
Codex findings to review: <paste>
```

### Call B: Codex reviews Claude findings

Same approach, mirrored prompt. Codex challenges Claude's findings.

**If Codex fails after preflight** - skip Phase 2 and record the sanitized failure category in the report; rely on intra-Claude convergence only.

**Phase 2 reviewer always AGREEs** - sycophancy. If >70% of findings come back as AGREE, abort and tell the user "Phase 2 debate degenerate, don't trust it - verify manually".

## Phase 3 - Synthesis (main agent)

Artifacts:
1. `claude_findings` (6 agents, post-dedup)
2. `codex_findings` (empty when Codex was skipped or unavailable)
3. `claude_on_codex` (cross-review verdicts, only when Codex completed)
4. `codex_on_claude` (cross-review verdicts, only when Codex completed)

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

## Output format

```markdown
## Code Review - PR #N

**Verdict: <Ready to Merge | Needs Attention | Needs Work>**
<One sentence on what to do next.>

Reviewers: 6 Claude subagents (3 generic + Architecture + Security + Deployment) + <Codex status: passed | skipped by user | unavailable after preflight>.
Diff base: `<base/ref used for the review, or staged/HEAD for non-branch scopes>`.
Codex: <passed | skipped by user | unavailable after preflight: sanitized reason>.
Convergence: <X findings caught by 2+ agents, Y by 1 agent + Codex; omit the Codex count when Codex was not used>.

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

## Verdict guidelines

- **Ready to Merge** - 0 Critical (including contested), 0 confirmed High; ≤2 Medium; nothing in Verify.
- **Needs Attention** - 1-2 confirmed High, or several Medium, or 1 contested Critical, or any [INTENT-VERIFY] present.
- **Needs Work** - any confirmed Critical, ≥3 confirmed High, a critical-path test gap, or a broken deploy procedure.
