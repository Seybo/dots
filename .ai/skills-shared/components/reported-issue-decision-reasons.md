# Reported Issue decision reasons

Use this policy after Manager presents a Fix or Skip assessment for one
Reported Issue. It applies equally to Autoimplement and Autofix.

## Retain the proposed reason

The text after the em dash in Manager's displayed `Recommendation: Fix — ...`
or `Recommendation: Skip — ...` line is the proposed durable reason. Retain
that exact text with the issue ID, recommendation, and resulting decision only
in the current conversation.

An Unclear assessment has no decision or proposed decision reason. Its initial
clarification question persists nothing. After the operator answers, reassess
once: when the reply makes Fix or Skip unambiguous and supplies the factual
basis, apply the operator-reasoning rules below. Ask for a separate decision
only when the operator's intended outcome remains ambiguous.

## Interpret the operator's decision

Any unambiguous affirmative in direct response to Manager's recommendation
accepts Manager's recommendation. This includes `go`, `yes`, `ok`, `okay`,
`accept`, `approved`, `sounds good`, and equivalent clear language. Store the
exact displayed recommendation reason unchanged.

When the operator chooses the opposite outcome without a reason, Manager asks
one concise follow-up question and persists nothing. Begin with `[MM_NTF]`,
name the issue and proposed opposite outcome, and ask why that outcome is
correct. Run no helper and create no Work Cycle until the reason is known.

Apply these rules whenever the operator supplies reasoning for an opposite
decision or an Unclear clarification:

1. Manager must briefly paraphrase the reasoning to confirm what it understood.
   The durable reason must remain self-contained and preserve the operator's
   actual meaning so a future agent can understand it without this conversation.
2. If Manager cannot understand the reasoning confidently, it asks one precise
   clarification question and persists nothing.
3. If Manager understands but disagrees, it says so explicitly, explains why,
   persists nothing, and asks for the operator's explicit confirmation before
   proceeding.
4. If Manager understands and agrees, it may condense the reasoning into one
   concise factual sentence without changing its meaning, then store the implied
   or explicit decision immediately.
5. After a disagreement, explicit operator confirmation authorizes storing the
   operator's decision and faithfully condensed reason despite Manager's stated
   objection.

Questions, details requests, unrelated messages, and genuinely ambiguous
replies remain non-decisions and persist nothing.

## Store and render

Map Fix to `approved` and Skip to `skipped`. Run exactly one workflow decision
helper for one operator reply, using this argument shape:

```text
store-decision <id> <approved|skipped> <shell-escaped-reason>
```

Pass the complete reason as one safely shell-escaped argument. Never interpolate
an unescaped reason into a shell command. Do not trim, paraphrase, categorize,
or regenerate a retained recommendation reason before storage.

The helper validates and stores the decision and reason together. Its output
begins with the exact stored values:

```text
Decision: <approved|skipped>
Reason: <exact stored reason>
```

Preserve those lines exactly in the operator-facing result while following the
calling workflow's normal routing for any subsequent issue, Work Cycle, final
checks, completion, or optional squash output.
