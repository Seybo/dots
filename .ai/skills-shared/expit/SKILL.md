---
name: expit
description: >-
  Explicit-only skill that explains a supplied or recent conversation subject
  using ordered example approaches. Invoke only with /skill:expit.
disable-model-invocation: true
---

# Expit

Explain one subject using the ordered examples in this skill. This is a command-only skill.

## Invocation

```text
/skill:expit [subject]
```

Do not invoke this skill automatically from an ordinary explanation request. Wait for an explicit slash command. A new invocation starts with the best-fitting explanation example.

## Resolve the subject

Use the first source that produces a clear subject:

1. Text supplied after the invocation. Treat the full text as authoritative, including when it is phrased as a question.
2. The nearest preceding substantive conversation topic from either the user or assistant. Skip commands, approvals, greetings, and meta-discussion about Expit itself.
3. If neither source is clear, ask the user what to explain and stop instead of guessing.

## Establish the facts

Before explaining, perform proportionate read-only investigation when the conversation does not establish the answer. Investigation is encouraged: inspect relevant code, local documentation, current external documentation, or other focused sources as needed.

Do not edit files, run write-capable operations, or mutate external systems. State unresolved uncertainty instead of inventing details. Keep the same established facts across every approach for one invocation; later approaches change the explanation, not the answer.

## Apply the examples

The entries below are examples of explanation approaches. Use them as examples: imitate the way an example makes its subject understandable, but adapt it to the current subject. Do not copy its domain terms, facts, entities, headings, or incidental formatting into an unrelated explanation.

Examples demonstrate explanation structure only. They do not establish facts, policy, correctness, or the expected conclusion. Determine independently whether a claim is right, wrong, partly right, or unresolved. Do not assume disagreement or rebuttal is appropriate merely because an example contains it.

Before the first response, rank the examples by how well their explanation structure fits the current subject:

- Prefer a complete-flow trace when the user needs to understand what happened through an ordered process.
- Prefer a claim-by-claim analysis when the user needs to evaluate criticism, competing claims, or a proposed fix.
- When examples fit equally well, prefer their listed order.

Apply exactly one example per response and preserve the ranking for the invocation.

After an attempt:

- If another unused example remains, end with: **“Try the next explanation approach? Reply with exact bare `next`.”**
- Only the immediate exact bare reply `next` continues with the same subject, established facts, and next-ranked unused example.
- Any other reply ends the active sequence and is handled normally.
- After the final example, say that no more explanation approaches remain and stop.
- An exact bare `next` outside an active continuation does not invoke Expit.

## Explanation examples, in order

### Example 1 — Complete-flow trace

#### Lactate’s complete flow

1. The PDF contains Lactate twice:

   - PDF page 20 — direct result:

     ```text
       LACTATE | PHOTOMETRY | 36.9 mg/dL
     ```

   - PDF page 5 — Summary Report:

     ```text
       LACTATE | 36.9 mg/dL
     ```

2. During the first import, the page 20 occurrence was selected as the direct result because it contains the detailed test context, including technology and governing report section.

3. That direct result was saved as:

   ```text
     Lactate 36.9 mg/dL — Bad — record 184
   ```

4. The page 5 occurrence was recognized as a secondary display of the same result. It was intentionally not stored because doing so would create a second Lactate record for the same test and date.

5. On the second import, the Source was already pending with 106 saved records. The importer loaded those records and found Lactate record 184 in the database.

6. When it reread the PDF:

   - page 20 matched already-saved record 184;
   - page 5 was again identified as the secondary Summary Report copy.

7. Therefore Lactate has two separate source-item dispositions:

   ```text
     Already saved:
     Lactate 36.9 mg/dL — record 184

     Intentionally omitted:
     Summary Report: LACTATE 36.9 mg/dL —
     secondary display of already-saved record 184.
   ```

8. Other already-saved Tests appear only under Already saved when the PDF contains one direct occurrence. Lactate and the other eleven Summary Report items also appear under Intentionally omitted because each has an additional secondary occurrence.

The omitted item is the Summary Report appearance, not the Lactate result itself.

### Example 2 — Claim-by-claim analysis

#### One HeyReach page approval flow

1. Hermes prepares one exact request:

   ```text
     campaignId: 562355
     limit: 100
     offset: 0
   ```

2. Hermes explains the request to the operator.

3. Hermes asks for approval for that page only.

4. Hermes waits for the operator’s response.

5. After approval, Hermes runs one command:

   ```text
     status-fetch-page \
       --campaign <gtm-campaign> \
       --heyreach-campaign 562355 \
       --offset 0
   ```

6. The command fetches only offset 0. It cannot automatically fetch the next page.

7. If offset 100 is needed, Hermes must start a new explanation and approval cycle.

---

#### Reviewer claim 1

> There is no approval because status-fetch-page has no --approve-fetch flag.

This is wrong because the required approval gate is in the Hermes workflow, where the operator can actually see and approve the request.

The CLI cannot see:

```text
  the explanation
  the Slack approval
  which operator approved
  what request the operator saw
```

Therefore, the absence of a flag does not mean the agent workflow lacks an approval gate.

---

#### Reviewer claim 2

> Adding --approve-fetch would make the executable reject unapproved requests.

This is the main reasoning error.

The executable could check only whether this text is present:

```text
  --approve-fetch
```

It could not check whether operator approval actually happened.

Hermes could run this without asking anyone:

```text
  status-fetch-page ... --approve-fetch
```

The executable would treat it as approved. The flag therefore proves caller intent, not operator approval.

---

#### Reviewer claim 3

> This should match --approve-push and --confirm.

This comparison mixes different protections.

The live push uses:

```text
  --approve-push --plan-key <key>
```

The important part is plan-key. It identifies a specific planned push, and the executable verifies that the live payload still matches it. That is a machine-checkable gate protecting an irreversible send.

A proposed fetch command would have only:

```text
  --approve-fetch
```

It would have no request key, approval record, or operator identity. It would not be bound to:

```text
  campaignId
  offset
  limit
```

So it would not provide the same protection as the push gate.

--confirm is also an accidental-use guard around a local lifecycle mutation. status-fetch-page performs a provider read and saves one local artifact; it does not send prospects or change the HeyReach campaign.

---

#### What the reviewer is right about

A developer can bypass Hermes and run this directly:

```text
  status-fetch-page ...
```

No CLI flag stops that.

If preventing direct developer use were a requirement, a flag could add friction. But it would still not prove operator approval.

---

#### Why the reviewer’s requested fix is unnecessary

The story defines an agent-run flow, not a standalone approval system inside the executable.

Request-specific approval is enforced through:

```text
  Hermes skill instructions
  default SOUL instructions
  GTM SOUL instructions
  one page per command
  a required pause before every next page
```

The proposed boolean flag would duplicate the instruction without verifying it. It would make the command look safer without adding real approval evidence.
