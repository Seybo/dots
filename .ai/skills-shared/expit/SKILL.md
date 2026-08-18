---
name: expit
description: >-
  Explicit-only skill that explains a supplied or recent conversation subject
  using ordered example approaches. Invoke only with /expit or /skill:expit.
disable-model-invocation: true
---

# Expit

Explain one subject using the ordered examples in this skill. This is a command-only skill.

## Invocation

```text
/skill:expit [subject]
/expit [subject]
```

Do not invoke this skill automatically from an ordinary explanation request. Wait for an explicit slash command. A new invocation always starts from the first explanation example.

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

Try the examples in their listed order. Apply exactly one example per response.

After an attempt:

- If another example remains, end with: **“Try the next explanation approach? Reply with exact bare `next`.”**
- Only the immediate exact bare reply `next` continues with the same subject, established facts, and next example.
- Any other reply ends the active sequence and is handled normally.
- After the final example, say that no more explanation approaches remain and stop.
- An exact bare `next` outside an active continuation does not invoke Expit.

## Explanation examples, in order

### Example 1

### Lactate’s complete flow

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
