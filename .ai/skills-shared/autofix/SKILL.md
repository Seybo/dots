---
name: autofix
description: >-
  Store inline review comments from the current branch's GitHub pull request and
  display its first unresolved reported issue. Command-only skill.
disable-model-invocation: true
---

# Autofix

Run the helper without arguments from the current checkout:

```text
/Users/inseybo/.ai/skills-shared/autofix/bin/autofix
```

The only supported invocation is:

```text
/skill:autofix
```

Use the current checkout to discover the pull request. Run the helper immediately
without confirmation. Return its stdout unchanged, with no introduction,
summary, code fence, or follow-up interaction.

Local clipboard review extraction is implemented by a later task.
