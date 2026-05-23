---
name: agent-permissions
description: Update or explain Claude Code and Pi permissions/allowlists. Use when the user asks about permission prompts, allowlisting commands, where permission files live, or how Pi permissions work.
---

# Agent Permissions

Use this skill when changing or explaining agent permissions for Claude Code and/or Pi.

## Canonical reference

Read this first:

```text
/Users/inseybo/.dots/refs/dev-env/agent-permissions.md
```

It records locations, Pi extension behavior, update workflow, and gotchas.

## Default rule

Unless the user explicitly says **Pi only** or **Claude only**, update **both** permission systems:

- Claude Code: `/Users/inseybo/.claude/settings.json` plus any relevant repo `.claude/settings*.json`.
- Pi: `/Users/inseybo/.dots/.pi/agent/permission.settings.json` plus any relevant repo `.agents/permission.settings*.json`.

## Local vs global selection rule

Memoize the scope decision before editing:

- Use **repo-local** permission files for command shapes tied to one checkout, repo layout, app folders, local scripts, local DBs, or workflow-specific paths. Prefer local files for relative path allows such as `find app*`, `find docs*`, `sqlite3 db/...`, or repo `_mydev` scripts.
- Use **global** permission files only for broadly reusable, low-risk command families that should work the same in most repos, such as `pwd`, `git status`, `git diff`, `rg`, `grep`, `head`, `sed -n`, and `python3 -m json.tool`.
- If the user asks to reduce prompts for commands seen in a specific repo and does not explicitly request global behavior, default to repo-local.
- If a repo-local file should stay private, use `.claude/settings.local.json` and `.agents/permission.settings.local.json`; ensure the Pi local file is ignored or excluded from git.

## Procedure

1. Read the canonical reference above.
2. Inspect the current permission files before editing.
3. Choose repo-local vs global using the selection rule above; when in doubt for repo-specific prompts, use repo-local.
4. Prefer narrow, read-only command shapes.
5. Avoid broad executor allow rules unless explicitly approved (`python*`, `pytest*`, `xargs*`, `sh -c*`, arbitrary `bash(*)`).
6. Preserve existing `deny` / `ask` safety rules.
7. Edit JSON carefully.
8. Validate JSON with `python3 -m json.tool <file> >/dev/null`.
9. QA with the exact command shape that prompted, if safe.
10. If a new gotcha is discovered, append it to `/Users/inseybo/.dots/refs/dev-env/agent-permissions.md`.

## Pi-specific reminder

Pi permission prompts in this setup come from the `agentic-af` permission extension, not Pi core. The extension loads:

```text
~/.pi/agent/permission.settings.json
<repo>/.agents/permission.settings.json
<repo>/.agents/permission.settings.local.json
```

Bash pipelines are split and checked segment-by-segment; the strictest segment wins.
