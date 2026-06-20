---
name: draftit
description: >-
  Create the next draftNN folder under /Volumes/dev/_tasks/<project> and write selected
  conversation context/text into task.md for later conversion via /taskit <project> draftNN.
  Command-only skill. Invoke only via /draftit.
---

# Draftit

This is a command-only skill.

## Invocation

Use only:

```text
/draftit help
/draftit <project> <context-reference-or-text>
```

Examples:

```text
/draftit help
/draftit gtm the above plan
/draftit gtm Name: Add CSV export Epic: 33001 Context: the implementation plan you just wrote
/draftit foo Create a story for adding CSV export support
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
     Draft-to-story flow:
     1. Run /draftit <project> <context> to create /Volumes/dev/_tasks/<project>/draftNN/task.md.
     2. Edit task.md and fill in # Story details with Name and Epic, OR include them in the /draftit call itself, e.g. /draftit gtm Name: Add CSV export Epic: 33001 Context: the plan above.
     3. Run /taskit <project> draftNN to create the Shortcut story.
     4. /taskit renames draftNN to <story_id>-<slug> after Shortcut returns the story ID.
     ```
   - extract `<project>` as the first token after `/draftit`
   - take all remaining text after the project name as the draft request
   - if the project or draft request is missing, ask the user to provide both, e.g.:
     ```text
     /draftit gtm the above plan
     ```
   - if the draft request includes explicit `Name:` and `Epic:` fields before optional `Context:`, use those values in `# Story details`; otherwise leave them blank

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
   - Preserve useful markdown structure from the source content.

4. **Ensure draft has Shortcut-ready structure:**
   - The draft should be usable by `/taskit <project> draftNN` later.
   - Every draft must start exactly with this scaffold:
     ```md
     # Story details

     Name: {explicit name, if provided}
     Epic: {explicit epic, if provided}

     # Context

     {draft content}
     ```
   - Leave `Name` and `Epic` blank unless the user explicitly included `Name:` and `Epic:` in the `/draftit` call. Do not infer, fill, or invent them.
   - If the request includes `Context:`, use the text after `Context:` as the draft content request and do not duplicate `Name:` / `Epic:` under `# Context`.
   - If the source content already includes a `# Story details` section, do not preserve it as the first section; place the source content under `# Context` instead unless doing so would duplicate irrelevant metadata.

5. **Find next draft folder name:**
   - list first-level folders under `/Volumes/dev/_tasks/<project>/` matching exactly `draftNN`, where `NN` is a two-digit positive integer
   - choose the smallest positive integer not already used, starting at `01`
   - format the folder with two digits: `draft01`, `draft02`, ... `draft99`
   - if `draft01` through `draft99` all exist, stop and ask the user how to proceed
   - examples:
     - no drafts → `draft01`
     - `draft01` exists → `draft02`
     - `draft01` and `draft03` exist → `draft02`

6. **Create folder and file:**
   - create directory:
     ```text
     /Volumes/dev/_tasks/<project>/draftNN
     ```
   - create file:
     ```text
     /Volumes/dev/_tasks/<project>/draftNN/task.md
     ```
   - if the target folder or file already exists unexpectedly, stop and ask the user how to proceed

7. **Write `task.md`:**
   - write the resolved/scaffolded markdown
   - if content does not end with a newline, add exactly one trailing newline

8. **Return paths clearly:**
   - show the draft name, e.g. `draft01`
   - show the full draft folder path
   - show the full `task.md` path
   - remind the user they can run:
     ```text
     /taskit <project> draftNN
     ```

## Important Notes

- The first argument is always the project name
- Create only; do not modify existing drafts
- Do not create project folders automatically
- Do not add extra files
- Do not auto-use this skill without the explicit `/draftit` command
