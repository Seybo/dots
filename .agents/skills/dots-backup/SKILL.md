---
name: dots-backup
description: Repo-local dots backup monitor. Reports active backup destinations, covered/excluded folders, last run/status when known, and backup coverage overlaps. Runs stored backup commands, with dry-run-first agent behavior for syncs.
---

# Dots Backup

Repo-local skill for monitoring and running backups from the dots repo.

## Usage

```bash
# Default report
ruby .agents/skills/dots-backup/scripts/dots_backup.rb

# Use a specific inventory file
ruby .agents/skills/dots-backup/scripts/dots_backup.rb --inventory path/to/inventory.yml

# Public-safe template; real inventory is config/inventory.yml and is gitignored
.agents/skills/dots-backup/config/inventory.example.yml

# Run a stored command
ruby .agents/skills/dots-backup/scripts/dots_backup.rb --run dots-to-extreme --type dry-run
ruby .agents/skills/dots-backup/scripts/dots_backup.rb --run dots-to-extreme --type backup
ruby .agents/skills/dots-backup/scripts/dots_backup.rb --run dots-to-extreme --type check

# Use a custom status/log directory
ruby .agents/skills/dots-backup/scripts/dots_backup.rb --status-dir path/to/status
```

Exit codes:

- `0` = report completed without findings, or run was launched into a sibling tmux pane
- `1` = report completed with findings such as coverage overlaps
- `2` = usage or fatal error

## Current behavior

- Reads private local `.agents/skills/dots-backup/config/inventory.yml` by default
- Keeps `.agents/skills/dots-backup/config/inventory.example.yml` as the public-safe committed template
- Prints active backup entries with included folders, excluded folders, last run, and status
- Prints `unknown` when data is not available instead of guessing
- Reports coverage overlaps between active backup entries
- Launches stored `dry-run`, `backup`, and `check` commands into a sibling tmux pane after printing the exact command
- Aborts if no sibling tmux pane is available; backup commands must not run hidden inside the agent tool call
- Stores generated pane runner scripts and run status/logs under `.agents/skills/dots-backup/state/runs` by default; generated state is gitignored
- Streams visible command output through `tee` in the sibling pane and writes JSON status when the command finishes
- Uses skill-managed run status files for future report `last run` and `status` values

## Agent run rule

When the user asks to run a backup/sync and that inventory entry has a `dry-run` command, launch the `dry-run` first in a sibling tmux pane, then stop. After it finishes, summarize the stored status/log if asked. Do not launch the real `backup` command until the user replies `go`.

## Invocation

When `/skill:dots-backup` is invoked, run the default report immediately:

```bash
ruby .agents/skills/dots-backup/scripts/dots_backup.rb
```

Setup changes should go through `.agents/skills/dots-backup/config/inventory.yml`.
