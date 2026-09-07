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

Repository mode is default-allow so normal skills, interpreters, tests, helpers, task paths, custom tools, and read-only `systemctl` queries do not require per-skill exceptions.

Keep the ask list short. Add a command family only when it represents a concrete, high-impact operation in this environment, such as:

- privilege or host service changes
- host/global package changes
- mass or irreversible filesystem operations
- process or tmux destruction
- destructive Git history, branch, stash, worktree, config, or remote operations
- external mutations and package publishing

Normal `git add`, `git rm`, ordinary `git commit`, literal non-resetting branch creation with `git checkout -b`, `git checkout --no-track -b`, or `git switch -c`, and exact non-force `git push -u origin <literal-branch>` or `git push --set-upstream origin <literal-branch>` remain allowed. Upstream pushes to `main`, `master`, `HEAD`, full refs, other remotes, multiple or dynamic refspecs, tags, deletion, force options, existing-branch switches, resetting or forced creation, path restoration, branch deletion or renaming, and other destructive or remote Git operations remain guarded. Agent authorization rules still decide when branch creation or push is permitted. Literal `rm` and plain `rmdir` targets are allowed when their resolved deletion paths stay inside the repository. `rmdir -p` remains guarded. Ordinary local `rsync` is allowed; remote transfers, deletion, source-file removal, and custom remote-shell options remain guarded.

Direct `edit` and `write` calls still prompt for files that were untracked and Git-ignored when Repository mode started, and for Git metadata. Repository-root `agents_tmp/` contents are the exception: they are disposable and remain mutable after reload, while the directory itself and symlink escapes remain guarded. In Repository and Unattended modes, direct mutations in OS temporary directories are blocked with guidance to use this visible, never-commit scratch directory. Literal deletion commands also prompt for other startup-ignored targets, repository escapes, and dynamic targets that cannot be resolved safely. A literal `cd` resolving to the current working directory is treated as a no-op when evaluating a later deletion; actual directory changes remain guarded. Default `kill $(cat agents_tmp/<name>.pid)` is allowed when that resolved literal scratch file contains one positive numeric PID; explicit signals, other paths, missing or invalid files, and other process selectors remain guarded. Skill rules cannot bypass these checks or the high-impact Bash ask list.

Repository mode is not a sandbox. Unknown executables are allowed and can hide operations that the visible command matcher cannot inspect. Use Ask mode for operation-by-operation approval and an OS sandbox for untrusted code.

## Shell command safety

When processing dynamically discovered paths, first list the paths, then run the follow-up command on those literal paths in a separate tool call. Avoid combining discovery with execution, deletion, or file-writing when the work can be expressed safely as two operations.

For `find`, approval-required examples include `-exec`, `-execdir`, `-ok`, `-okdir`, `-delete`, `-fprint`, `-fprint0`, `-fprintf`, and `-fls`.

## Permission request log

The extension records every approval-required operation as one JSON line. Entries include the timestamp, mode, prompt status, working directory, tool, reason, and request detail capped at 1,200 characters. The private local log persists across sessions and may contain sensitive command arguments, so never commit or share it without reviewing the content.

Log paths:

- macOS: `~/Library/Logs/pi/repo-permissions.jsonl`
- Linux: `pi/repo-permissions.jsonl` under the `XDG_STATE_HOME` directory when set; otherwise `~/.local/state/pi/repo-permissions.jsonl`

When the user asks to review a permission log, copy it into repository `agents_tmp/`, scan the copy for sensitive data, and read it. Immediately after a successful read, truncate the source log and remove the local review copy before discussing findings or changing policy. This ensures the next review contains only new requests.

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
- SSH access through conservative `ssh`, `scp`, and `sftp` forms may be approved for one exact destination for the current session. Quoted local `scp` paths may use simple environment variables. The safe options `-q`, `-o BatchMode=yes`, and `-o ConnectTimeout=<seconds>` may precede the destination.
- Conservative mutating `curl` requests may be approved for one exact loopback HTTP origin for the current session. Grants support `localhost`, `127.0.0.1`, and `::1`; redirects, proxies, alternate connection targets, config files, Unix sockets, and custom Host headers remain guarded.
- High-impact commands prompt even when a trusted skill rule matches.
- Unattended and non-interactive operations that require approval are blocked.
