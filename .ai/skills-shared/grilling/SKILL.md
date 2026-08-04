---
name: grilling
description: Stress-test a plan through grounded, one-question-at-a-time interviewing. Use when the user wants to stress-test a plan before building, or uses any 'grill' trigger phrases. When invoked on a plan or task file, save the settled results into that file.
---

Interview me relentlessly until the plan is implementation-ready, but remain grounded in the user's request, any written plan, established domain terminology, prior answers, and codebase evidence.

## File-backed and idea-only sessions

At the start, determine whether the invocation identifies an existing source file. This includes an explicit file path or a selector such as `draft04` that unambiguously resolves to one plan or task file through the current workflow's established resolution rules. If a selector resolves to multiple files, ask which file is authoritative before grilling.

For a file-backed session:

- Read the complete source file before interviewing.
- Keep the interview read-only while questions remain. Do not rewrite the file after each answer.
- When no material open points remain, automatically update that same file before the final summary. The file-backed invocation authorizes this source-file update; do not require a second save request.
- Integrate settled decisions into the relevant sections, replace obsolete or conflicting statements, remove alternatives that were resolved, and preserve unrelated content and the file's established structure. Do not append a transcript or a generic grilling report.
- Before editing, determine whether version control can restore the current content. If it cannot, create and verify a backup outside the affected path first.
- Update only the identified source file. Do not edit implementation code, related plans, roadmaps, or other files unless the user explicitly requests them.
- Re-read the updated file and verify it reflects every settled decision and explicit deferral before reporting completion.
- If the user explicitly requests report-only or no-save grilling, do not update the file.

When no source file is identified, the workflow is strictly read-only; summarize and stop when grilling is complete.

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

Stop when no material open points remain. For a file-backed session, save and verify the source file first. Then summarize the settled decisions, any explicitly deferred issues, and the updated file path.
