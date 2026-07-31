---
name: grilling
description: Stress-test a plan through grounded, one-question-at-a-time interviewing. Use when the user wants to stress-test a plan before building, or uses any 'grill' trigger phrases.
---

Interview me relentlessly until the plan is implementation-ready, but remain grounded in the user's request, any written plan, established domain terminology, prior answers, and codebase evidence.

The user may provide either a developed plan or only a feature idea.

- With a developed plan, stress-test its unresolved decisions.
- With a feature idea, help form the plan through grounded questions.
- Do not require the user to write a plan first.

When starting from a feature idea:

1. Treat the user's stated outcome and constraints as settled.
2. Explore the codebase for existing behavior, terminology, and conventions.
3. Begin with the highest-level material gap, usually desired behavior or scope.
4. Resolve product decisions before implementation details that depend on them.
5. Build on prior answers without inventing unstated requirements or hypothetical alternatives.

Before asking a question, classify the relevant point as:

- **Settled** — explicitly specified or previously answered.
- **Discoverable** — answerable from the codebase or documentation; investigate it instead.
- **Open** — genuinely unanswered and materially affects behavior, scope, architecture, safety, or operability.

Ask only about open points.

Do not:

- invent alternatives merely because they are theoretically possible
- reinterpret established terms without evidence
- ask the user to reconfirm settled decisions
- turn a separate work cycle, phase, pane, process, or role into a new session or context unless the plan says so
- introduce speculative requirements, abstractions, recovery behavior, metadata, validation, or configurability
- challenge a settled decision without identifying a concrete contradiction, implementation blocker, or material risk

A question is valid only when:

1. The answer is not already present.
2. The codebase or documentation cannot answer it.
3. Different answers would materially change the implementation or expose a concrete risk.

When challenging an existing decision, quote the conflicting statements or name the concrete risk. Do not present an invented alternative as though the plan implied it.

Use this format:

### Question N: <question>

**Why this is open:** <specific missing information, contradiction, or risk>

**Recommendation:** <recommended answer grounded in the plan and evidence>

Ask one question at a time and wait for feedback.

Cover material concerns such as boundaries, contracts, failure behavior, security, compatibility, and operations only when relevant to this plan. Prefer KISS/YAGNI; exhaustive grilling means finding all material unresolved decisions, not enumerating every imaginable design.

Stop when no material open points remain. Summarize the settled decisions and any explicitly deferred issues.
