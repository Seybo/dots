---
name: explain-file
description: >-
  Explain how a file works paragraph by paragraph, with special attention to
  context, edge cases, weird code, and why the implementation looks the way it does.
  Command-only skill. Invoke only via /explain-file.
---

# Explain File

This is a command-only skill.

## Invocation

Use only:

```text
/explain-file <path-to-file>
```

Do not auto-use this skill from general explanation requests. Wait for the explicit slash command.

## What it does

Explain how the target file works paragraph by paragraph.

## Instructions

1. Read the file provided in the command argument.
2. Look up how the file is used in the wider context before answering.
3. Focus on subtleties and edge cases.
4. Be extra diligent when code looks weird or hard to grasp for humans, for example regexes.
5. Focus not only on **what** the code does, but also on **why** it is written that way and what might be surprising about it.
6. Compose a list of curiosity-driving questions and answer them.
7. When referencing code, always make it clickable using this format:
   - `<relative-path>:<line-number>`

## Output expectations

- Explain the file paragraph by paragraph or section by section, depending on the file shape
- Include surrounding context so the explanation is useful, not just literal
- Call out hidden assumptions, tricky control flow, regex behavior, and failure modes
- Prefer insight over paraphrase
