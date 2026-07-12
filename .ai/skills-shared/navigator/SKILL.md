---
name: navigator
description: Command-only index for discovering this user's agent skills, slash commands, prompt templates, abbreviations, and workflow tools. Invoke only via /skill:navigator <question>; update inventory only with /skill:navigator update.
disable-model-invocation: true
---

# Navigator

Navigator is a command-only map of the user's agent capabilities.

## Invocation rule

Use this skill only when the user invokes it explicitly as:

```text
/skill:navigator <question>
```

Do not auto-trigger this skill from ordinary questions. Do not treat vague phrases such as "what skills do I have?" or "update navigator" as valid invocations unless they are passed through `/skill:navigator`.

## Update mode

Only mutate Navigator files when the user invokes exactly:

```text
/skill:navigator update
```

For update mode:

1. Run the update script from this skill directory:

   ```bash
   cd /Users/inseybo/.dots/.ai/skills-shared/navigator && ruby scripts/update_inventory.rb
   ```

2. Read `references/uncategorized.generated.md`.
3. If new useful items are uncategorized, update `references/capability-map.md` and `references/aliases.md` with human-friendly categories and trigger phrases.
4. Re-run the update script so `uncategorized.generated.md` reflects the categorization.
5. Summarize changed files.

Never rewrite `SKILL.md` during update mode unless the user explicitly asks to change Navigator behavior.

## Active projects mode

Source of truth:

```text
/Users/inseybo/.dots/refs/dev-env/active-projects.md
```

When the user explicitly invokes Navigator to list, explain, add, or remove active projects, read and update only this file.

For requests like `/skill:navigator add this project to active`:

1. Resolve the current git repo root from the same agent session, using `git rev-parse --show-toplevel` or an explicit user-provided path.
2. If no repo root can be resolved, ask the user for the path.
3. Verify the resolved path is an actual repo root.
4. Add the repo root under `## Projects` if absent.
5. Keep project paths sorted.
6. Do not scan `/Volumes/dev/projects` or infer additional projects unless the user explicitly asks to refresh the list.

## Question-answering mode

For any other `/skill:navigator ...` invocation:

1. Read `references/capability-map.md` first.
2. Read `references/aliases.md` when the query uses vague or natural-language wording.
3. Read `references/inventory.generated.md` for the current scanned list of skills, prompt commands, and abbreviations.
4. If the user asks how to use a specific skill or command, read its source file listed in the inventory before answering.
5. If the user asks about Pi mechanics, read the relevant Pi docs under `/Users/inseybo/.asdf/installs/nodejs/24.0.1/lib/node_modules/@earendil-works/pi-coding-agent/docs`.

Keep answers short and navigational: what to use, when to use it, and where the source of truth lives.

## Safety

- Do not execute write-capable external tools while answering normal questions.
- Update mode may only update Navigator's own generated/reference files.
- Never print secrets or credentials found while scanning files.
