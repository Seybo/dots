---
name: draftit
description: >-
  Create the next draftNN folder under /Volumes/dev/_tasks/<project> from a
  required task slug and conversation context. Local-only drafts are the
  default; epic: makes a registered Shortcut project Shortcut-ready.
  Command-only skill. In Pi, invoke via /skill:draftit; /draftit is also
  accepted where that alias is exposed.
disable-model-invocation: true
---

# Draftit

This is a command-only skill.

## Invocation

```text
/skill:draftit help
/draftit help
/draftit <project> <task-slug> [epic: <id>] [context-reference-or-text]
/draftit <task-slug> [epic: <id>] [context-reference-or-text]
```

Examples:

```text
/draftit add-csv-export
/draftit add-csv-export the above plan
/draftit shaka_gtm add-csv-export epic: 33001
```

The first token is a project only when it matches a registered project key in
`~/.ai/skills-shared/components/projects.yml`. Otherwise infer the project from
the current checkout. The next or first token respectively is the required task
slug.

Do not auto-use this skill from a general drafting request. Wait for the explicit slash command.

## What it does

Create the next available `draftNN` folder under:

```text
/Volumes/dev/_tasks/<project>/
```

Then write `task.md` from the requested context. Use it later with:

```text
/taskit <project> draftNN
```

## Instructions

1. **Parse and validate arguments:**
   - if the only argument is `help`, show this help text and stop
   - resolve `<project>` from an explicit registered key or the current checkout using [`task-resolution.md`](../components/task-resolution.md)
   - require `<task-slug>` after an explicit project, or as the first token when the project is inferred
   - require the slug to match `^[a-z][a-z0-9-]*$`
   - extract optional `epic: <id>` from the remaining request text
   - all remaining text is optional draft context; if it is absent, use an empty context body
   - do not inspect Pi session logs, prompt templates, other task directories, Git history, or unrelated repository files to infer missing context
   - do not accept `name:`; the positional slug is the task name

2. **Resolve the project:**
   - read `task_provider` from `~/.ai/skills-shared/components/projects.yml`
   - if the project is not registered, stop and tell the user to add it to the registry
   - if its task root does not exist, create `/Volumes/dev/_tasks/<project>/`
   - `epic:` is valid only for `task_provider: shortcut`; reject it for local projects

3. **Resolve context:**
   - for references such as `the above plan`, use the relevant conversation content
   - for literal text, use that text
   - for commits, PRs, review comments, or external threads, inspect the source and rewrite it as self-contained context
   - if no context was supplied, leave the context body empty; do not ask a question

4. **Write useful task content:**
   - use the task slug unchanged as the concise task title
   - lead `# Context` with the user/product problem, not implementation details
   - include expected behavior and acceptance criteria when context supports them
   - do not add implementation planning; `/workit` creates `steps.md` later
   - put source links in `## References`

5. **Use the correct task structure:**
   - local-only draft:
     ```md
     # Context

     ## {task slug}

     {draft content}
     ```
   - Shortcut-ready draft:
     ```md
     # Story details

     Name: {task slug with `-` replaced by spaces}
     Epic: {explicit epic id}

     # Context

     {draft content}
     ```

6. **Choose the draft folder:**
   - scan only first-level folders matching exactly `draftNN`, where `NN` is a two-digit positive integer
   - choose the smallest missing number from `01` through `99`
   - stop if all are used

7. **Create the draft:**
   - create `/Volumes/dev/_tasks/<project>/draftNN/`
   - create `task.md` only; never modify an existing draft
   - add exactly one trailing newline

8. **Report:**
   - show the draft name, draft folder, and `task.md` path
   - remind the user to run `/taskit <project> draftNN`

## Important Notes

- Local-only drafts are the default.
- `epic:` is the only Shortcut-ready trigger.
- Do not register projects automatically.
- Do not add extra files.
- Do not auto-use this skill without the explicit `/draftit` command.
