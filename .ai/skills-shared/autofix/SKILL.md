---
name: autofix
description: >-
  Fetch and display one GitHub inline review comment from an explicitly supplied
  discussion URL. Command-only skill.
disable-model-invocation: true
---

# Autofix

Run the helper with the supplied URL as its only argument:

```text
/Users/inseybo/.ai/skills-shared/autofix/bin/autofix <comment-url>
```

The only supported invocation is:

```text
/skill:autofix https://github.com/<owner>/<repo>/pull/<number>#discussion_r<id>
```

Use the URL supplied with the explicit skill invocation. Do not inspect the
current checkout or infer a pull request. Run the helper immediately without
confirmation. Return its stdout unchanged, with no introduction, summary, code
fence, or follow-up interaction.
