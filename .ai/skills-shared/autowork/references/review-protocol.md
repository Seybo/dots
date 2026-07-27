# Review protocol — Claude reviews, finding handling, debates

Read this file when a step reaches review, findings, or a Pi/Claude disagreement.

## Claude review protocol

Claude reviews should follow `/gtm-revit`-style rules, not a minimal blocker-only review.

Important: `/gtm-revit` does not require running RuboCop or RSpec. During normal step reviews, Claude should not run RSpec, RuboCop, linters, formatters, or any other test/check command — not full-suite and not targeted. Claude should inspect the diff/files and Pi's reported `checks_run`. Pi may run targeted checks during implementation/fix turns, and `/autowork` runs configured full final checks after all planned steps are accepted.

Claude should suggest everything that makes sense according to `/gtm-revit` rules and classify checklist items with:

```text
PASS
MINOR
BLOCKER
```

Expected summary shape:

```text
Summary: <N> BLOCKER / <M> MINOR / <K> PASS
Recommendation: accept | fix | split
```

`/autowork` prompt should ask Claude to review the last commit against the current step only:

- read `task.md`
- read `steps.md`
- use full `steps.md` for context
- scope findings to current `Step N`
- do not require future-step behavior unless current changes block or contradict future work
- do not edit repo files
- do not run RSpec, RuboCop, linters, formatters, or any other test/check command during step review — not full-suite and not targeted
- write review to the assigned `autowork-log/reviews/...` file
- write status JSON when done

## Handling findings

Claude review status JSON must include a machine-readable `findings` array. Use an empty array when there are no `BLOCKER` or `MINOR` findings. Each actionable finding should include `id`, `severity`, `title`, `body`, and `recommendation`.

After Claude review, Pi classifies all findings at once in a resolution file:

```text
autowork-log/resolutions/step1_pi_review1_result.md
```

For each finding, Pi chooses one:

```text
accept
accept_with_alternative_fix
dispute
follow_up
needs_user
```

Rules:

- Valid findings that are clearly in this task's scope must be fixed now, even when the fix naturally belongs to a later step.
- `MINOR` findings must be fixed now, even when they are outside this task's original scope, as long as they are minor/local/low-risk.
- Use `follow_up` only for valid non-minor findings that are outside this task's scope; `/autowork` carries them into `final_summary.md` instead of debating/fixing them.
- Use `dispute` only when the finding is invalid, not reachable, or contradicted by repo/task evidence.
- `needs_user` pauses immediately when product/scope input is required.
- Accepted fixes are implemented first.
- `/autowork` commits accepted code changes.
- Claude reviews the fix commit.
- Remaining disputes are recorded in `autowork-log/debates/stepN_debates.md` and debated up to `max_debate_rounds_per_disagreement`.
- If Claude agrees with Pi during debate, the finding is treated as resolved without code changes.
- If Pi accepts Claude's position during debate, `/autowork` sends a normal fix prompt, commits the fix, and sends it back to Claude for review.
- If both agents still disagree after the round limit, `/autowork` pauses for user arbitration. This pause is intentional because the manager cannot decide which agent is correct.

## Disagreement procedure

Disagreement escalation starts when Pi disputes a Claude finding or fix requirement:

- Claude says `BLOCKER`, Pi thinks it is invalid or not reachable
- Claude says `MINOR`, Pi thinks it is invalid or not reachable
- Claude suggests fix A, Pi thinks fix B is better
- Claude says prior fix is still wrong

Per-step debate file:

```text
autowork-log/debates/step1_debates.md
```

Each disagreement gets its own section:

```md
## D1 — Review 1 finding B: <short title>

### Round 1 — Claude
...

### Round 1 — Pi
...
```

`/autowork` facilitates debate rounds, but it must not pick a winner between Pi and Claude on its own.

Round flow:

1. send Pi's dispute/defer rationale to Claude
2. Claude either agrees with Pi or still disagrees
3. if Claude still disagrees, send Claude's response back to Pi
4. Pi either accepts and requests a fix turn, or still disagrees
5. repeat until agreement or `max_debate_rounds_per_disagreement`

If agreement happens:

- Claude agrees with Pi: no code change is required for that finding; continue to the next debate/finding/step
- Pi accepts Claude's concern: send a fix turn, commit it as `Step N fix M`, then send the fix commit back to Claude for review

If still unresolved after the round limit, pause for operator arbitration. After the operator decides:

- if a fix is needed, continue with an explicit instruction so Pi can implement it and `/autowork` can commit/re-review it
- if the finding is rejected or deferred, keep the rationale in the disagreement file and continue only with explicit operator approval

The `debates/` directory stores disagreement records and per-round responses.
