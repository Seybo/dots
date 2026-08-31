---
name: agent-permissions
description: Update or explain Claude Code and Pi permissions/allowlists. Use when the user asks about permission prompts, allowlisting commands, where permission files live, or how Pi permissions work.
---

# Agent Permissions

Use this skill when changing or explaining agent permissions for Claude Code and/or Pi.

## Canonical reference

Read this first:

```text
~/.dots/refs/dev-env/agent-permissions.md
```

It records the current permission models, source locations, update workflow, and gotchas.

## Default rule

Unless the user explicitly says **Pi only** or **Claude only**, consider both systems. They do not share a configuration model:

- Claude Code uses permission rules in `~/.claude/settings.json` and repository `.claude/settings*.json` files.
- Pi uses the owned `repo-permissions` extension at `~/.dots/.pi/agent/extensions/repo-permissions/`.

Do not create or restore `permission.settings.json` files for Pi.

## Pi modes

Choose the smallest mode that matches the request:

1. **Repository** — default inside Git. Allows ordinary tools and commands while prompting for explicit high-impact operations.
2. **Unattended** — uses Repository policy but blocks approval-required operations immediately so work never waits for input.
3. **Ask** — prompts for every operation except narrow trusted-skill allowances and Pi clipboard screenshot reads.
4. **Unrestricted** — allows everything for the current session.

Mode choices and approvals never persist.

## Pi policy

Repository mode is default-allow so normal skills, interpreters, tests, helpers, task paths, and custom tools do not require per-skill exceptions.

Keep the ask list short. Add a command family only when it represents a concrete, high-impact operation in this environment, such as:

- privilege or host service changes
- host/global package changes
- mass or irreversible filesystem operations
- process or tmux destruction
- destructive Git history, branch, stash, worktree, config, or remote operations
- external mutations and package publishing

Normal `git add`, `git rm`, and ordinary `git commit` remain allowed. Literal `rm` and plain `rmdir` targets are allowed when their resolved deletion paths stay inside the repository. `rmdir -p` remains guarded.

Direct `edit` and `write` calls still prompt for files that were untracked and Git-ignored when Repository mode started, and for Git metadata. In Repository and Unattended modes, direct mutations in OS temporary directories are blocked with guidance to use the repository's visible, never-commit `agents_tmp/` directory. Literal deletion commands also prompt for startup-ignored targets, repository escapes, and dynamic targets that cannot be resolved safely. Skill rules cannot bypass these checks or the high-impact Bash ask list.

Repository mode is not a sandbox. Unknown executables are allowed and can hide operations that the visible command matcher cannot inspect. Use Ask mode for operation-by-operation approval and an OS sandbox for untrusted code.

## Trusted skill rules

Trusted top-level user and project skills may declare narrow `allowed-tools` rules for Ask mode. Pi's standard space-delimited scalar and the existing YAML list form are supported:

```yaml
allowed-tools: read grep
```

```yaml
allowed-tools:
  - "bash(~/.dots/no_stow/bin/agent-brave-search *)"
```

Keep these rules scoped to the exact trusted wrapper or tool family the skill owns. Third-party package skills are not eligible.

Do not add skill rules for ordinary Repository-mode work; it is already allowed.

## Procedure

1. Read the canonical reference.
2. Determine whether the request concerns Claude Code, Pi, or both.
3. Inspect the prompted operation and identify the rule that caused it.
4. For Pi Repository mode:
   - remove stale or overly broad ask rules when ordinary work is prompting
   - add an ask rule only for a concrete high-impact operation
   - prefer path-aware `read`, `edit`, or `write` when one clearly expresses the same action
5. For Pi Ask mode, use a narrow trusted-skill allowance only when a trusted wrapper or tool is the intended boundary.
6. For Claude Code, preserve deny/ask protection and follow its global versus repository-local settings convention.
7. Add behavior-focused specs for every Pi policy or lifecycle change.
8. Run the complete Pi extension specs and verify Pi loads without diagnostics.
9. Update the canonical reference when durable behavior changes.

## Claude Code reminders

- Prefer global rules only for broadly reusable, low-risk read-only commands.
- Prefer repository-local rules for checkout-specific paths and workflows.
- Avoid broad executor allows such as arbitrary Python, shell wrappers, `pytest`, or `xargs`.
- Run `/doctor` after adding or removing Claude Code `Bash(...)` rules.

## Pi reminders

- Repository mode starts automatically only after Git root and startup Git-ignored file discovery succeeds.
- Ask mode is the fallback outside Git or after discovery failure.
- Unattended mode is available only after Repository discovery and blocks instead of prompting.
- Unrestricted mode is session-only.
- Repository mode allows ordinary outside task/workflow paths; it is not filesystem confinement.
- Pi clipboard images named `pi-clipboard-<UUID>.png` are readable from the OS temporary directory in Repository and Ask modes.
- SSH access through conservative `ssh`, `scp`, and `sftp` forms may be approved for one exact destination for the current session. Quoted local `scp` paths may use simple environment variables.
- High-impact commands prompt even when a trusted skill rule matches.
- Unattended and non-interactive operations that require approval are blocked.
