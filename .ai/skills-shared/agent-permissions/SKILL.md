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
- Use **global** permission files for broadly reusable, low-risk command families that should work the same in most repos, such as `pwd`, `man *`, `col -b`, `git status`, `git diff`, `rg`, `grep`, `head`, `sed -n`, and `python3 -m json.tool`.
- If the user asks to reduce prompts for commands seen in a specific repo and does not explicitly request global behavior, default to repo-local.
- If the user asks to update repo-local permissions across all active projects, read `/Users/inseybo/.dots/refs/dev-env/active-projects.md` and update only the repo roots listed there.
- NEVER assume the repo path for repo-local rules from the agent's current working directory or from this dotfiles checkout. If the prompted command uses relative paths or otherwise needs repo-local permissions, first confirm the actual repo path from the prompt context, an explicit user-provided path, or a `pwd` from that same agent session. If the repo path is unknown, ask the user before editing any repo-local permission file.
- If a repo-local file should stay private, use `.claude/settings.local.json` and `.agents/permission.settings.local.json`; ensure the Pi local file is ignored or excluded from git.

## Procedure

1. Read the canonical reference above.
2. Inspect the current permission files before editing.
3. If the prompted command is unsafe or intentionally restricted, do **not** allowlist it. Instead:
   - explain briefly why it should stay restricted
   - find a safer read-only alternative command shape when possible
   - QA the safer alternative if it is safe
   - if the alternative is reusable, update the current repo's `AGENTS.md` with a concise safe-command substitution note so future agents avoid the unsafe shape
4. Choose repo-local vs global using the selection rule above; when in doubt for repo-specific prompts, use repo-local.
5. Prefer safe, read-only command shapes at the right level of generality:
   - Do **not** over-narrow universally safe documentation/inspection commands to one subject. For example, if prompted for `man tmux`, suggest/allow `man *` globally, not `man tmux` only.
   - Use broad global rules for non-mutating documentation/listing/filtering helpers such as `man *`, `col -b`, `pwd`, `ls`, `rg`, `grep`, `head`, `tail`, and `sed -n`.
   - Use narrower rules when a command is repo-specific, path-specific, writes files, shells out, executes code, or has dangerous flags.
6. Avoid broad executor allow rules unless explicitly approved (`python*`, `pytest*`, `xargs*`, `sh -c*`, arbitrary `bash(*)`).
7. Preserve existing `deny` / `ask` safety rules.
8. On every update, perform a redundancy check before and after editing:
   - Remove exact duplicate rules in the edited files.
   - Do not add a repo-local rule that is already covered by a global rule unless the local rule intentionally narrows or documents repo-specific behavior.
   - Do not add a narrower rule when an existing same-scope broader rule already safely covers the command shape.
   - Keep intentional overlap when `ask` / `deny` rules override broad `allow` rules for safety.
9. Edit JSON carefully.
10. Validate JSON with `python3 -m json.tool <file> >/dev/null` immediately after each permission-file edit, before continuing.
    - If a Pi permission JSON file becomes invalid, stop and repair it before any more permission work; the Pi permission extension can fail future tool calls while settings are invalid.
11. QA with the exact command shape that prompted, if safe. If the original command is unsafe, QA the safer alternative instead.
12. If a new gotcha is discovered, append it to `/Users/inseybo/.dots/refs/dev-env/agent-permissions.md`.
13. If a discovery suggests the `agent-permissions` workflow itself should change, suggest a skill update to the user instead of silently changing this skill.

## Claude Code-specific reminder

When updating Claude Code permissions from outside Claude Code, remind the user to run `/doctor` in Claude Code after changes, especially after adding or removing `Bash(...)` rules.

## Pi-specific reminder

Pi permission prompts in this setup come from the `agentic-af` permission extension, not Pi core. The extension loads:

```text
~/.pi/agent/permission.settings.json
<repo>/.agents/permission.settings.json
<repo>/.agents/permission.settings.local.json
```

Bash pipelines are split and checked segment-by-segment; the strictest segment wins.

Avoid `?` wildcards in Pi permission patterns. They can compile to invalid regexes in the permission extension, e.g. `bash(mv -n .../????-*)` can fail with `Nothing to repeat`. Prefer `*`-based path constraints plus safety flags such as `mv -n`.
