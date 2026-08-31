---
name: grilling
description: Stress-test a plan through grounded, one-question-at-a-time interviewing. Use when the user wants to stress-test a plan before building, or uses any 'grill' trigger phrases. When invoked on a plan or task file, save the settled results into that file.
---

Interview me relentlessly until the plan is actionable, but remain grounded in the user's request, any written plan, established domain terminology, prior answers, and codebase evidence.

## Top-down grilling

Grill from broad understanding to narrow detail.

Before asking detailed questions, summarize the task as a plain-language,
end-to-end description and let the user correct that understanding.

Then proceed in this order:

1. Goal and scope
2. General behavior or workflow
3. Rules, boundaries, and unresolved outcomes
4. Implementation details, only when required to resolve a material decision or make the plan actionable

Omit implementation details that do not affect behavior, scope, risk, or a
decision the plan must settle.

Ask questions in the order they affect the workflow. Do not jump to a later
step or lower level of detail while an earlier part remains unclear.

Before each question, briefly restate only the established context relevant to
the next question. The grilling conversation should progressively become a
coherent description of the feature, not a collection of disconnected
questions.

## File-backed and idea-only sessions

At the start, determine whether the invocation identifies an existing source file. This includes an explicit file path or a selector such as `draft04` that unambiguously resolves to one plan or task file through the current workflow's established resolution rules. Read and follow [`task-resolution.md`](../components/task-resolution.md) when resolving a draft, Task, or Feature selector. If a selector resolves to multiple files, ask which file is authoritative before grilling.

For a file-backed session, read the complete source file before interviewing. For a draft or Task with the exact leading Feature reference from [`task-resolution.md`](../components/task-resolution.md), load the linked Feature before `task.md` as shared goal, scope, and constraint context, then let the source file win conflicts.

When the authoritative source matches
`$DEV_ROOT/_tasks/<registered-project>/features/<feature-slug>.md`:

- Grill exactly one capability per session. Use a capability named by the invocation or handoff; otherwise ask which capability to develop before continuing.
- Preserve unrelated research and unresolved questions without asking about them or treating them as deferred by this session.
- Treat the Feature as read-only shared context. Never edit, reorganize, or back it up during Grillme.
- Preserve the settled capability and any explicit deferrals in the final conversation summary so Grillme can offer Draftit.

For every other file-backed session:

- Keep the interview read-only while questions remain. Do not rewrite the file after each answer.
- When each material point is settled, discoverable, or explicitly deferred, automatically update the source file before the final summary. The invocation authorizes this update; do not require a second save request.
- Integrate settled decisions into the relevant sections, replace obsolete or conflicting statements, remove resolved alternatives, and preserve unrelated content and the file's established structure. Do not append a transcript or generic grilling report.
- Put every explicitly deferred question in a final `# Deferred decisions` section using the complete Question / Why this is open / Recommendation format. Remove questions once resolved, omit the section when empty, and do not infer a deferral merely because the user has not answered yet.
- Before editing, determine whether version control can restore the current content. If it cannot, create and verify a backup outside the affected path first.
- Update only the identified source file. Do not edit implementation code, related plans, roadmaps, or other files unless the user explicitly requests them.
- Re-read the updated file and verify it reflects every settled decision and explicit deferral before reporting completion.

When no source file is identified, the workflow is strictly read-only; preserve the settled result in the final conversation summary.

The user may provide either a developed plan or only a feature idea.

- With a developed plan, stress-test its unresolved decisions.
- With a feature idea, help form the plan through grounded questions.
- Do not require the user to write a plan first.

When starting from a feature idea:

1. Treat the user's stated outcome and constraints as settled.
2. Explore the codebase for existing behavior, terminology, and conventions.
3. Follow Top-down grilling before moving to narrower questions.
4. Build on prior answers without inventing unstated requirements or hypothetical alternatives.

Treat references as evidence to inspect, not as proof. Investigate relevant local code and documentation, official or upstream sources, and focused external sources only when they are likely to resolve a material decision. Do not research merely to satisfy a checklist.

Before asking a question, classify the relevant point as:

- **Settled** — explicitly specified or previously answered.
- **Discoverable** — answerable from relevant source material, existing implementations, documentation, or proportionate external research; investigate it instead.
- **Open** — genuinely unanswered after relevant discovery and materially affects behavior, scope, architecture, safety, or operability.

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
2. Relevant evidence cannot answer it.
3. Different answers would materially change behavior, scope, architecture, safety, operability, or another decision the plan must settle.

When challenging an existing decision, quote the conflicting statements or name the concrete risk. Do not present an invented alternative as though the plan implied it.

Use this format:

### Question N: <question>

**Why this is open:** <specific missing information, contradiction, or risk>

**Recommendation:** <recommended answer grounded in the plan and evidence>

Treat the recommendation as the proposal the user should accept, reject, or
correct. End the turn with the recommendation. Do not append another question,
prompt, or restatement after it; that makes the decision target ambiguous.

Ask one question at a time and wait for feedback. When the user explicitly defers a question or says they cannot answer it, record it for `# Deferred decisions`, do not ask it again, and continue with the next point.

Cover material concerns such as boundaries, contracts, failure behavior, security, compatibility, and operations only when relevant to this plan. Prefer KISS/YAGNI; exhaustive grilling means finding all material unresolved decisions, not enumerating every imaginable design.

Stop when every material point is settled, discoverable, or explicitly deferred. For a non-Feature file-backed session, save and verify the source file first. For a Feature-backed session, verify the Feature stayed unchanged. Then summarize the settled decisions, any explicitly deferred issues, and the authoritative file path when present.
