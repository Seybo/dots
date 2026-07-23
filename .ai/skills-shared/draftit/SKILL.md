---
name: draftit
description: >-
  Create the next draftNN folder under /Volumes/dev/_tasks/<project> and write selected
  conversation context/text into task.md for later conversion via /taskit <project> draftNN.
  Local-only drafts are the default; include epic: <id> to make a Shortcut-ready draft.
  Can infer the project from the current checkout when it is not passed.
  Command-only skill. In Pi, invoke via /skill:draftit; /draftit is also
  accepted where that alias is exposed.
disable-model-invocation: true
---

# Draftit

This is a command-only skill.

## Invocation

In Pi, use either:

```text
/skill:draftit help
/draftit help
/draftit <project> [epic: <id>] [name: <title>] [context-reference-or-text]
/draftit [epic: <id>] [name: <title>] [context-reference-or-text]
```

When the first token is the name of an existing project folder under
`/Volumes/dev/_tasks/`, treat it as `<project>` and the rest as the draft request.
Otherwise infer `<project>` from the current working directory and treat the whole
input as the draft request. Drafts have no story ID, so only the project is inferred.

Local-only drafts are the default. Including `epic: <id>` in the invocation makes
the draft Shortcut-ready only when the selected project's registry entry has
`task_provider: shortcut`. For `task_provider: local` projects, `epic:` is invalid and
must be rejected instead of creating a Shortcut-ready draft. `name: <title>` is optional;
if it is omitted for a Shortcut-ready draft, infer a concise title from the conversation context.

Examples:

```text
/draftit help
/draftit shaka_gtm the above plan
/draftit shaka_gtm epic: 33001 name: Add CSV export
/draftit my_budget_app the above plan
/draftit the above plan   # project inferred from the current checkout
```

Do not auto-use this skill from a general drafting request. Wait for the explicit slash command.

## What it does

Create the next available zero-padded `draftNN` folder under the selected project:
```text
/Volumes/dev/_tasks/<project>/
```

Then write a `task.md` file inside it using the requested conversation context/text.

The result is intended to be used later with:

```text
/taskit <project> draftNN
```

## Instructions

1. **Parse command arguments:**
   - if the only argument is `help`, show this help text and stop:
     ```text
     Draft flow:
     1. Run /draftit <project> to create a local-only /Volumes/dev/_tasks/<project>/draftNN/task.md from the current conversation context.
     2. Add epic: <id> only for a project with `task_provider: shortcut` when you want the draft to become a Shortcut story later, e.g. /draftit shaka_gtm epic: 33001 name: Add CSV export.
     3. Run /taskit <project> draftNN later.
     4. /taskit converts local-only drafts to sequential local task folders and Shortcut-ready drafts to Shortcut stories.
     ```
   - determine `<project>` and the draft request:
     - if the first token after `/draftit` matches an existing folder under `/Volumes/dev/_tasks/`, treat it as `<project>` and take all remaining text as the draft request
     - otherwise infer `<project>` from the current working directory using [`~/.ai/skills-shared/components/task-resolution.md`](../components/task-resolution.md), and take the whole input after `/draftit` as the draft request
   - read the selected project's `task_provider` from `~/.ai/skills-shared/components/projects.yml`
   - extract `epic: <id>` from the draft request when present; this is the only trigger for a Shortcut-ready draft on `task_provider: shortcut` projects
   - if `epic: <id>` is present for a `task_provider: local` project, stop and report that the project is local/manual-only; do not create the draft
   - extract optional `name: <title>` from the draft request when present
   - do not expect or ask for a `Context:` field; the context should come from the conversation or any literal remaining request text
   - if the project cannot be resolved or inferred, ask the user to provide it, e.g.:
     ```text
     /draftit shaka_gtm
     ```
   - if there is no literal draft text after removing `epic:` / `name:`, use the current conversation context; if there is no usable conversation context, ask the user what the draft should cover

2. **Resolve and validate project:**
   - project root:
     ```text
     /Volumes/dev/_tasks/<project>/
     ```
   - if it does not exist, stop and tell the user the project was not found
   - do not create project folders automatically

3. **Resolve draft content from the request:**
   - If the request references prior conversation context, such as `the above plan`, `that plan`, `the previous answer`, or `the implementation plan`, use the relevant prior assistant/user content from the conversation.
   - If the request contains literal text, use that literal text.
   - If the request points to a commit, PR, review comment, chat thread, or similar external context, inspect what is needed to understand the task, then rewrite it as a self-contained story. The main task body must make sense without opening the references.
   - Preserve useful markdown structure from the source content.

4. **Shape the task content:**
   - Infer a concise task title from the request or conversation, unless `name: <title>` was provided. Keep it short enough to become a readable folder slug when `/taskit <project> draftNN` converts the draft.
   - Lead with the user/product problem in plain English. The first prose paragraph under `# Context` should explain what is wrong and why it matters without technical implementation details.
   - Keep code paths, service names, schema details, and suggested implementation approaches out of the main problem statement.
   - Include expected behavior and acceptance criteria when the context supports them.
   - If the change affects docs or operator-facing behavior, include a docs update in acceptance criteria.
   - Do not add an `Implementation notes`, `Technical notes`, `Suggested shape`, or similar implementation-planning section to `task.md`. `/workit` creates `steps.md` later for implementation planning.
   - Only include implementation details in `task.md` when they are essential domain facts that a future session is likely to miss and that affect the acceptance criteria; otherwise omit them.
   - Put PRs, commits, review comments, chat links, and similar source material in a final `## References` section. Do not quote long review comments or chat logs in the main body; summarize the decision or context instead.

5. **Ensure draft has the right structure:**
   - The draft should be usable by `/taskit <project> draftNN` later.
   - For local-only drafts, put a concise second-level heading immediately under `# Context`; `/taskit` uses the first meaningful heading/content to derive the local task folder slug, so do not let the first meaningful line be a long paragraph.
   - If `epic:` is absent, create a local-only draft that starts exactly with:
     ```md
     # Context

     ## {concise task title}

     {draft content}
     ```
   - If `epic:` is present, create a Shortcut-ready draft that starts exactly with:
     ```md
     # Story details

     Name: {explicit name, or concise inferred title from conversation}
     Epic: {explicit epic id}

     # Context

     {draft content}
     ```
   - For Shortcut-ready drafts, `Epic` must come from the explicit `epic:` argument. `Name` may come from explicit `name:`; otherwise infer a concise title from the conversation. If no reasonable name can be inferred, ask the user for `name:`.
   - Do not include or preserve a `Context:` marker in `task.md`; it is not part of the invocation interface.
   - If the source content already includes a `# Story details` section, do not preserve it as the first section unless this run is Shortcut-ready; place the source content under `# Context` instead unless doing so would duplicate irrelevant metadata.

6. **Find next draft folder name:**
   - list first-level folders under `/Volumes/dev/_tasks/<project>/` matching exactly `draftNN`, where `NN` is a two-digit positive integer
   - choose the smallest positive integer not already used, starting at `01`
   - format the folder with two digits: `draft01`, `draft02`, ... `draft99`
   - if `draft01` through `draft99` all exist, stop and ask the user how to proceed
   - examples:
     - no drafts → `draft01`
     - `draft01` exists → `draft02`
     - `draft01` and `draft03` exist → `draft02`

7. **Create folder and file:**
   - create directory:
     ```text
     /Volumes/dev/_tasks/<project>/draftNN
     ```
   - create file:
     ```text
     /Volumes/dev/_tasks/<project>/draftNN/task.md
     ```
   - if the target folder or file already exists unexpectedly, stop and ask the user how to proceed

8. **Write `task.md`:**
   - write the resolved/scaffolded markdown
   - if content does not end with a newline, add exactly one trailing newline

9. **Return paths clearly:**
   - show the draft name, e.g. `draft01`
   - show the full draft folder path
   - show the full `task.md` path
   - remind the user they can run:
     ```text
     /taskit <project> draftNN
     ```

## Important Notes

- The first token is the project name only when it matches an existing project folder; otherwise the project is inferred from the current checkout and the whole input is the draft request
- `epic: <id>` is the only Shortcut-ready trigger; without it, drafts are local-only
- Do not ask the user for `Context:`; use the conversation context by default
- Create only; do not modify existing drafts
- Do not create project folders automatically
- Do not add extra files
- Do not auto-use this skill without the explicit `/draftit` command
