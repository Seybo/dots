---
name: shortcut
description: Read Shortcut stories, create minimal Shortcut stories, and update story descriptions from markdown files using the shared Ruby Shortcut CLI. Use when the user asks to read story/stories from IDs or links, explicitly asks to create a Shortcut story with a name and epic ID, or asks to update a story description.
---

# Shortcut

Use this skill to read Shortcut stories, create minimal Shortcut stories, and update story descriptions through the shared Ruby CLI.

## When to use

Use this skill when the user asks to read Shortcut stories, including phrasing like:

- `read story 33002`
- `read stories 33002 33003`
- `read this story: <Shortcut URL>`
- `read these stories: <Shortcut URLs>`
- `please read Shortcut story 33002 and summarize it`

## Authentication

The Shortcut API token must be available as:

```bash
SHORTCUT_KEY
```

Never print, log, or expose `SHORTCUT_KEY`.

## Story ID extraction

Extract story IDs from:

- plain numeric IDs: `33002`
- Shortcut story URLs containing `/story/<id>/`, for example:
  `https://app.shortcut.com/workspace/story/33002/story-name`

De-duplicate IDs while preserving their first-seen order.

## CLI path

Prefer this CLI path:

```bash
~/.pi/agent/extensions/shortcut/scripts/shortcut.rb
```

If that path does not exist, use the repo-local path from this dotfiles repo:

```bash
~/.dots/.pi/agent/extensions/shortcut/scripts/shortcut.rb
```

## Read one story

```bash
ruby ~/.pi/agent/extensions/shortcut/scripts/shortcut.rb get-story 33002
```

## Read multiple stories

Run the CLI once per story ID:

```bash
ruby ~/.pi/agent/extensions/shortcut/scripts/shortcut.rb get-story 33002
ruby ~/.pi/agent/extensions/shortcut/scripts/shortcut.rb get-story 33003
```

Then use the returned JSON as context to answer the user's question.

## Create a story

Creating a Shortcut story is a write operation. Only create stories when the user explicitly asks to create a Shortcut story and provides, or confirms, both required fields:

- `name`
- `epic_id` or a Shortcut epic URL

The CLI always applies these defaults:

- Team: `AI Team` (`group_id`: `69d7e322-a521-4100-a632-a952962ce509`)
- Workflow: `GTM Engine` (`workflow_id`: `500027063`)
- State: `Ready for Development` (`workflow_state_id`: `500027065`)

Do not send `group_id`, `workflow_state_id`, `project_id`, labels, owners, or other optional fields for the minimal create command. Story description is optional and may come from a markdown file via `description_path`.

In Pi, prefer the friendly slash command:

```text
/shortcut-story-create "Story name" 123
```

Optionally include a markdown file path for the story description:

```text
/shortcut-story-create "Story name" 123 ./description.md
```

The second argument must be a valid Shortcut epic ID. A Shortcut epic URL is also accepted by Pi:

```text
/shortcut-story-create "Story name" https://app.shortcut.com/workspace/epic/123/epic-name
```

The Pi command also accepts the JSON form:

```text
/shortcut-story-create {"name":"Story name","epic_id":123}
/shortcut-story-create {"name":"Story name","epic_id":123,"description_path":"./description.md"}
```

For direct CLI usage, use JSON:

```bash
ruby ~/.pi/agent/extensions/shortcut/scripts/shortcut.rb create-story '{"name":"Story name","epic_id":123,"description_path":"./description.md"}'
```

For larger/safer shell input, use stdin:

```bash
printf '%s\n' '{"name":"Story name","epic_id":123}' | ruby ~/.pi/agent/extensions/shortcut/scripts/shortcut.rb create-story -
```

After creation, report the created story ID and URL from the returned JSON.

## Update story description

Updating a Shortcut story is a write operation. This skill currently only supports updating the story description from a markdown file.

Minimum arguments:

- one Shortcut story ID or story URL
- optional markdown file path ending in `.md` or `.markdown`

If the markdown path is omitted, find the task file automatically by story ID under `/Volumes/dev/_tasks/*/<story_id>-*/task.md`. Exactly one matching task folder must exist. When updating from a `task.md` that contains a `# Story details` section, strip that section before sending the description to Shortcut.

In Pi, users may invoke this with plain language containing `update story`, `update stories`, `update this story`, or `update these stories`, for example:

```text
update story 33002
update story 33002 ./description.md
update story https://app.shortcut.com/workspace/story/33002/story-name ./description.md
```

The explicit Pi command is:

```text
/shortcut-story-update 33002
/shortcut-story-update 33002 ./description.md
```

Direct CLI usage still requires an explicit markdown path:

```bash
ruby ~/.pi/agent/extensions/shortcut/scripts/shortcut.rb update-story 33002 ./description.md
```

For story-id-only update, the Pi command/skill resolves the task file path first, then calls the CLI with that path.

After update, report the updated story ID and URL from the returned JSON.

## Error handling

If the CLI reports that Shortcut is not configured, tell the user to set `SHORTCUT_KEY`.

If one story fails but others succeed, report which story failed and continue using the successful story data.

## Safety

Reading is safe to perform when requested. Creating is allowed only through the explicit minimal create-story flow documented above. Updating is allowed only for story descriptions from markdown files as documented above. Do not delete Shortcut resources unless a future skill version explicitly documents deletion.
