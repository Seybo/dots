# Review protocol — reviewer findings, handling, and debates

Read this file when a step reaches review, findings, or a worker/reviewer disagreement.

All human-readable review, classification, and debate artifacts must be copyable plain Markdown without tables, aligned columns, or cell layouts. Use headings and numbered finding blocks with one labeled field per line.

## Review protocol

`agent-reviewer` uses `/gtm-revit`-style depth, not a minimal blocker-only review. It may be Claude or Pi using Codex, as selected by `super_review_agent`.

During normal step reviews, the reviewer must not run RSpec, RuboCop, linters, formatters, or other checks. It inspects the diff/files and the worker's reported `checks_run`. The worker may run targeted checks during implementation/fix turns; `/autowork` runs configured full checks after all planned steps are accepted.

Classify checklist items as:

```text
PASS
MINOR
BLOCKER
```

Expected summary:

```text
Summary: <N> BLOCKER / <M> MINOR / <K> PASS
Recommendation: accept | fix | split
```

The reviewer prompt must:

- read `task.md` and `steps.md`
- review the last commit against the current step
- use full `steps.md` only as context
- not require future-step behavior unless current changes block or contradict it
- not edit repo files
- write the assigned human-readable review before status JSON

## Handling findings

Reviewer status JSON includes `findings`; use an empty array when there are no actionable findings. Each finding includes `id`, `severity`, `title`, `body`, and `recommendation`.

After review, Pi classifies all findings at once in:

```text
autowork-log/resolutions/step1_pi_review1_result.md
```

Allowed decisions:

```text
accept
accept_with_alternative_fix
dispute
follow_up
needs_user
```

Rules:

- Fix valid in-scope findings now, even when the fix naturally belongs to a later step.
- Fix `MINOR` findings now when they are local and low-risk, even outside original scope.
- Use `follow_up` only for valid non-minor out-of-scope findings.
- Use `dispute` only when repo/task evidence shows the finding is invalid or unreachable.
- `needs_user` pauses immediately.
- `/autowork` commits accepted changes, then sends the commit to `agent-reviewer`.
- Debate remaining disputes up to `max_debate_rounds_per_disagreement`.
- If the reviewer agrees with Pi, resolve without code changes.
- If Pi accepts the reviewer's position, send a normal fix turn, commit, and re-review.
- If disagreement remains at the limit, pause for operator arbitration.

## Disagreement procedure

The per-step record is:

```text
autowork-log/debates/step1_debates.md
```

Each disagreement has alternating reviewer and Pi rounds:

```md
## D1 — Review 1 finding B: <short title>

### Round 1 — Reviewer
...

### Round 1 — Pi
...
```

Round flow:

1. Send Pi's rationale to `agent-reviewer`.
2. The reviewer agrees or explains the remaining disagreement.
3. If disagreement remains, send the response back to Pi.
4. Pi accepts and requests a fix, or explains why it still disagrees.
5. Repeat until agreement or the configured limit.

`/autowork` facilitates the exchange but never picks a winner. After an operator decision, continue only with explicit approval. Keep rejected/deferred rationale in the debate file.
