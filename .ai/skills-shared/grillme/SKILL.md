---
name: grillme
description: >
  Interview the user relentlessly about a plan or design until reaching shared
  understanding, resolving each branch of the decision tree. Use when user wants
  to stress-test a plan, get grilled on their design, or mentions "grill me".
---

# grillme

Interview the user about a plan or design until both sides share the same model.
Walk the decision tree one branch at a time. Resolve dependencies between decisions
before moving deeper.

## Core behavior

- Ask **one question at a time**.
- For each question, include **your recommended answer**.
- Be direct and persistent. Do not skip unclear parts to be polite.
- Keep a running mental map of decisions, dependencies, risks, and open questions.
- If a question can be answered by reading or searching the codebase, inspect the
  codebase instead of asking the user.
- Do not dump a long questionnaire. The value is in following each answer to the
  next dependent decision.

## Workflow

1. Restate the plan in one or two sentences.
2. Identify the highest-leverage unresolved decision.
3. If the answer is discoverable in the repo, read/search the code and answer it.
4. Otherwise ask one question.
5. Provide your recommended answer directly under the question.
6. Wait for the user's answer.
7. After each answer, update the shared model, then choose the next dependent
   question.

## Question format

Use this shape:

```markdown
Question: <one focused question>

Recommended answer: <what I think you should choose, and why>
```

If code exploration answered the question, use:

```markdown
Checked in code: <what I looked at>

Answer: <what the code shows>

Next question: <one focused question>

Recommended answer: <what I think you should choose, and why>
```

## What to probe

Cover these areas as needed, but only one branch at a time:

- Goal and non-goals
- Users, operators, and failure modes
- Inputs, outputs, and source of truth
- Data model and state transitions
- API or CLI contract
- Idempotency and reruns
- Error handling and retries
- Security, privacy, and secret handling
- Migration and rollout plan
- Observability and debugging
- Tests and acceptance criteria
- Backward compatibility
- Cleanup, deprecation, and escape hatches

## Stop condition

Continue until all material branches are resolved or the user says to stop. At the
end, summarize:

- agreed decisions,
- remaining open questions,
- risks accepted,
- next implementation steps.
