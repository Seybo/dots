# Phases 1→2→3 — handoff, cross-review, synthesis, output format

Read this file when Phase 1 reviewers start returning.

## Phase 1 → Phase 2 handoff

Use provider-neutral artifact names:

- `panel_findings` = union of Generic 1-3 + Architecture + Security + Deployment
- `independent_findings` = output from the seventh independent generic reviewer
- `phase1-candidates.json` = deduplicated candidates with stable IDs for adjudication

In Claude mode, `panel_findings` come from Claude and `independent_findings` come from Codex CLI. In Codex mode, all findings come from isolated Pi/Codex sessions, but the seventh reviewer remains blind and independently prompted.

Dedup within `panel_findings`: if 2+ agents flagged the same hole (same file, line ± 5, same conceptual issue), merge with a note such as "reviewers: gen-1 + gen-3 + security". Convergence count is discovery signal only.

Before Phase 2, write every deduplicated candidate to `phase1-candidates.json`:

```json
{
  "candidates": [
    {
      "id": "P1",
      "source_group": "panel",
      "claim": "Short candidate claim",
      "severity": "HIGH",
      "trigger": "Exact condition required for the behavior",
      "sources": ["generic1", "security"]
    },
    {
      "id": "I1",
      "source_group": "independent",
      "claim": "Short candidate claim",
      "severity": "MEDIUM",
      "trigger": "Exact condition required for the behavior",
      "sources": ["independent"]
    }
  ]
}
```

Use `P1`, `P2`, ... for panel candidates and `I1`, `I2`, ... for independent candidates. Phase 2 decisions must reference these IDs exactly.

With 3 generic agents, **2 of 3 = high signal** and **3 of 3 = almost certain**. Claude-mode cross-model/cross-vendor convergence is stronger than Codex-only convergence. In Codex mode, agreement is useful but never describe it as independent cross-vendor confirmation.

**Specialists (Architecture / Security / Deployment) rarely converge with generic agents** because their mandates include classes generic agents often skip. Keep a specialist High or concrete Medium as a Phase 2 candidate without requiring convergence, but apply the same reachability evidence and validator gates before surfacing it.

**Convergence is NOT verification for control-flow, exception-semantics, or state-machine claims.** Before surfacing such a finding as High, independently trace the normal path and exact trigger per `references/hard-rules.md`. Agreement on a mechanism is not proof that it fires.

## Phase 2 — adversarial cross-review (parallel)

Launch both blind adjudicators concurrently when both source groups contain candidates:

- Adjudicator A reviews `independent_findings`.
- Adjudicator B reviews `panel_findings`.

Skip an adjudicator only when its source group has zero candidates. If the entire candidate manifest is empty, skip Phase 2 and run the validator with only `--candidates` and `--output`; it produces a valid clean summary.

Use this prompt in both directions, replacing the source label and candidates:

```
You are doing adversarial cross-review. Another blind reviewer panel produced
candidate findings. Decide each stable candidate ID exactly once:
- AGREE: real and actionable, with accepted reachability evidence
- DISAGREE: wrong, with the specific code/reason
- NEEDS_CONTEXT: available evidence cannot prove reachability; name what is missing

Be adversarial rather than agreeable. Convergence is not evidence. Absence from
vendor documentation is not evidence that another value occurs. Skip style and
preferences.

[INSERT HARD RULES BLOCK]

Project conventions: <paste>
Diff: <absolute diff path>
Candidates to review: <paste candidates for this source_group>

Return raw JSON only, without Markdown fences:
{
  "source_group": "panel | independent",
  "decisions": [
    {
      "id": "P1",
      "decision": "AGREE",
      "rationale": "Why the candidate is correct",
      "trigger": "Exact reachable condition",
      "mechanism": "Confirmed code path from trigger to consequence",
      "reachability_source": "task_contract | vendor_contract | existing_untouched_code | reproduction | schema_invariant",
      "evidence": "Concrete source citation proving the trigger is permitted"
    },
    {
      "id": "P2",
      "decision": "NEEDS_CONTEXT",
      "rationale": "Why current evidence is insufficient",
      "missing_evidence": "What would prove or disprove reachability"
    }
  ]
}
```

`DISAGREE` requires `id`, `decision`, and a non-empty `rationale`. `AGREE` without all evidence fields is invalid.
Claude mode:

- Adjudicator A is an Opus Task reviewing the independent Codex findings.
- Adjudicator B is Codex CLI reviewing the six-reviewer Claude panel.

Codex mode:

- Write two complete adjudication prompt files.
- Invoke `scripts/run-pi-reviewers --model gpt-5.6-sol --thinking high` once with both paths so both isolated Pi/Codex adjudicators run concurrently.
- Do not inherit the Phase 1 Terra model; both Phase 2 adjudicators are pinned to `openai-codex/gpt-5.6-sol` at high reasoning.
- Same-provider adjudication is a noise filter, not cross-vendor confirmation.

If any required adjudicator process fails, record the sanitized failure and put affected candidates in Verify Manually.

After both adjudicators return, run the deterministic gate before synthesis:

```bash
~/.ai/skills-shared/super-review/scripts/validate-adjudication \
  --candidates "$OUTPUT_DIR/phase1-candidates.json" \
  --adjudication "$OUTPUT_DIR/phase2/adjudicate-independent.md" \
  --adjudication "$OUTPUT_DIR/phase2/adjudicate-panel.md" \
  --output "$OUTPUT_DIR/adjudication-summary.json"
```

Pass only the adjudication files for source groups that contain candidates. A validation error stops the workflow; correct the malformed adjudication or mark unsupported AGREE decisions as NEEDS_CONTEXT. Do not synthesize around a validator failure.

The validator calculates agreement ratios. More than 70% AGREE from either adjudicator makes the entire Phase 2 degenerate. This is a hard gate, not a reporting suggestion: no AGREE candidate is actionable until a human manually verifies it.

## Phase 3 — synthesis (main agent)

Artifacts:

1. `panel_findings`
2. `independent_findings`
3. `phase1-candidates.json`
4. `adjudicator_on_independent`
5. `adjudicator_on_panel`
6. `adjudication-summary.json`

Read `adjudication-summary.json` first:

- If `is_degenerate` is true, put every ID in `manual_verification_candidate_ids` under Verify Manually. Do not put any of them in Must Fix, Should Fix, or actionable status findings.
- If `requires_manual_verification` is true because of NEEDS_CONTEXT, put those IDs under Verify Manually.
- Only IDs in `actionable_candidate_ids` may enter the decision tree below.
- In Autowork mode, any manual-verification ID requires `status: needs_user`, an empty `findings` array, and a concrete `question`. It must not enter the fix loop or consume a fix iteration.

Decision tree per validated candidate follows as an internal reference only. Do not reproduce this table in the report or any user-facing response:

| Source | Validated decision | Decision |
|---|---|---|
| Independent reviewer | AGREE | Surface with its reachability evidence |
| Independent reviewer | DISAGREE | Drop unless Critical, then Contested |
| Independent reviewer | NEEDS_CONTEXT | Verify Manually |
| Panel single reviewer | AGREE | Surface with its reachability evidence |
| Panel 2+ converged | AGREE | Surface only after validator acceptance |
| Panel candidate | DISAGREE | Drop unless Critical, then Contested |
| Any source | adjudicator unavailable | Verify Manually |

**[INTENT-VERIFY] findings ALWAYS surface** - silent behavior changes require author confirmation, not reviewer judgment.

**Contested Criticals are never dropped** - "⚠ Contested: <Disagreer> says <reason>" - the user resolves.

## Output format

The report must not contain Markdown tables, ASCII tables, aligned columns, or other cell layouts. Use the numbered blocks and labeled lines below so every field and explanation remains easy to select and copy.

```markdown
## Code Review - PR #N

**Verdict: <Ready to Merge | Needs Attention | Needs Work>**
<One sentence on what to do next.>

Agent mode: `<claude | codex>`.
Reviewers: <Claude mode: 6 Claude + 1 Codex | Codex mode: 7 isolated Pi/Codex reviewers>.
Diff base: `<base/ref used for the review, or staged/HEAD for non-branch scopes>`.
Reviewer status: <passed, partial with sanitized reason, or skipped by explicit user choice where allowed>.
Convergence: <X findings caught by 2+ reviewers, Y confirmed by an adjudicator>. Codex mode must add: `Same-vendor convergence; no cross-vendor confirmation.`

---

## Must Fix (Critical / High)

**1. [SEVERITY][category] file:line - headline**

**What**: 2-4 sentences with the actual code snippet quoted (use ``` markdown block).
The reader should not need to open the file to grasp the issue. Explain the
contradiction, conditions, failure scenario.

**Why it matters**: 1-2 sentences. Real impact.

**Reachability evidence**: `<reachability_source>` — concrete citation proving the trigger is permitted.

**Fix**: Concrete change. Code snippet if non-trivial.

_Caught by: <which agents converged>_

---

## Should Fix (Medium)

Shorter format: **headline + a one-or-two-line What + Fix**. "Why it matters" is omitted (at Medium impact it's usually obvious from the headline or What). Code snippet is omitted if the headline already named the location. Group by file when 3+ findings touch the same file.

```
**N. [MEDIUM][category] file:line - headline**

**What**: one or two lines. Concretely WHAT is wrong (not just "regex incomplete" - "regex misses `.rubocop.yml`, `.rspec`, `spec/`"). Not a full paragraph.

**Fix**: concrete change. Code snippet inline OK.

_Caught by: N/7._
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

- Every candidate listed by `manual_verification_candidate_ids`, with the missing evidence or degenerate-adjudicator reason. Never duplicate these under Must Fix or Should Fix.

---

## Clean (verified)

- TLS verification ✓
- API key from ENV ✓
- (etc - things confirmed clean to balance the negative findings)

---

## Stats

Pre-debate: <N> findings (panel: X, independent: Y). Adjudication: panel <agree>/<total> (<ratio>), independent <agree>/<total> (<ratio>), degenerate: <yes|no>. Post-debate: <surfaced> surfaced + <contested> contested + <verify> verify. False positive cut: <%>.
```

## Verdict guidelines

- **Ready to Merge** - 0 Critical (including contested), 0 confirmed High; ≤2 Medium; nothing in Verify.
- **Needs Attention** - 1-2 confirmed High, or several Medium, or 1 contested Critical, or any [INTENT-VERIFY] present.
- **Needs Work** - any confirmed Critical, ≥3 confirmed High, a critical-path test gap, or a broken deploy procedure.
