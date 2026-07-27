# Past findings — escaped-bug rubric

Every bug class that once escaped this pipeline (or was caught only by the human reviewer) is recorded here. This file is the review's institutional memory: it grows after each postmortem, and its lessons get folded into `references/hard-rules.md` or the subagent prompts once a class repeats.

## Postmortem procedure (after each review, once the user has posted or commented)

1. Which findings did THEY add that the skill did not catch? → gaps; add an entry to the table below with status `watch`.
2. Which findings did the skill produce that they did not use? → noise; consider a skip-list update.
3. If a class repeats (2+ occurrences), propose the encoding: a new HARD RULES block, a prompt change, or a synthesis rule. When the user approves and it lands, flip the entry's status to `encoded` and note where.

## Prompt-composition hook

When composing Phase 1 prompts, check this table for `watch` entries. Append each `watch` entry's one-line check to every reviewer prompt (after the HARD RULES BLOCK) as:

```
ACTIVE WATCH (recent escaped-bug classes, check each explicitly):
- <one-line check per watch entry>
```

`encoded` entries are already inside the HARD RULES BLOCK or a subagent prompt — do not duplicate them.

## Bug classes

| Class | Example of the miss | Status |
|---|---|---|
| Cross-field consistency | Approval gate filters by X but idempotency key is built from Y | encoded: CROSS-FIELD CONSISTENCY block |
| Silent behavior change | Validity 30d→24h not in PR description | encoded: [INTENT-VERIFY] category |
| Domain API limits | Apollo 50k results / 500-page cap ignored | encoded: DOMAIN KNOWLEDGE block |
| Diff line vs file line | Citing diff hunk positions as line numbers | encoded: LOCATION CITATIONS block + worktree |
| Block-list regex with holes | refresh_token / bearer / private_key not covered by redaction | encoded: Sensitivity-of-redaction analysis (Security prompt) |
| Severity inflation on exception flow | Compound-edge "error masking" tagged HIGH + "lost" though Ruby preserves `.cause` and the case needs a second simultaneous DB failure | encoded: PRECONDITION & SEVERITY DISCIPLINE + "convergence is not verification" (synthesis) |
| Self-corroborating diff | Behavior AND its test/fixture/comment edited together; green suite proves only that the check moved with the code | encoded: SELF-CORROBORATING DIFF block (oracle-0 caveat: the AC can share the false premise) |
| False external-API-shape premise | Every in-repo artifact (fixture, spec, comment, AC) shares the wrong payload shape; multi-fallback access (`a \|\| b \|\| c`) tells | encoded: IN-CODE TELLS note |
| Unsafe deletion blessed by its own rationale | Code removed as "redundant" though its own docstring says it ran at a different stage / on different data | encoded: DELETED CODE IS EVIDENCE block |

<!-- Add new escaped classes above this line with status `watch` until they are folded into hard-rules/prompts. -->
