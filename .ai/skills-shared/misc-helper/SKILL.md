---
name: misc-helper
description: >-
  Run small personal helper utilities from one command namespace. Command-only
  skill. In Pi, invoke via /skill:misc-helper; /misc-helper is also accepted
  where that alias is exposed. Currently supports davinci-kill, cache-clean,
  and tmux-bar-reset.
allowed-tools:
  - "bash(~/.ai/skills-shared/misc-helper/scripts/misc-helper *)"
disable-model-invocation: true
---

# Misc Helper

This is a command-only skill for small personal helper utilities that do not deserve separate skills.

## Invocation

In Pi, use either:

```text
/skill:misc-helper <helper>
/misc-helper <helper>
```

Currently supported:

```text
/misc-helper davinci-kill
/misc-helper cache-clean
/misc-helper tmux-bar-reset
```

## Behavior

1. Parse the first argument as the helper name.
2. Run only the matching helper listed below.
3. If the helper is unknown or missing, show the available helpers and stop.
4. Do not invent ad-hoc helpers. Add new helpers by updating this skill and `scripts/misc-helper`.

## Helpers

### tmux-bar-reset

Clear stuck tmux agent attention/running markers.

Run:

```bash
~/.ai/skills-shared/misc-helper/scripts/misc-helper tmux-bar-reset
```

The script clears tmux window/global options used by the agent attention bar and stops `agent-attention-notify --pane` watcher processes.

### cache-clean

Remove known-safe local cache/generated-data folders from this Mac, then inspect
other disk-space cleanup candidates. The script performs the standard cleanup;
the agent performs the read-only inspection below afterward.

Run:

```bash
~/.ai/skills-shared/misc-helper/scripts/misc-helper cache-clean
```

The script first asks the user to type `CLOSED` to confirm affected apps are closed
and browser-cpu-monitor is stopped. It warns that browser-monitor diagnostics
will be deleted without a backup.

The script removes only these paths:

- `~/Library/Application Support/Insta360/Insta360 Studio/previewer_cache`
- `~/Library/Application Support/Insta360/Insta360 Studio/log`
- `~/Library/Application Support/com.apple.wallpaper/aerials`
- `~/Library/Application Support/Claude/vm_bundles`
- `~/Library/Application Support/Claude/Cache`
- `~/Library/Caches/Homebrew/downloads`
- `~/Library/Caches/Google`
- `~/Library/Caches/BraveSoftware`
- `~/Library/Caches/com.brave.Browser`
- `~/Library/Caches/camoufox`
- `~/Library/Caches/Vivaldi`
- `~/Library/Caches/Cypress`
- `~/Library/Caches/ms-playwright`
- `~/Library/Caches/typescript`
- `~/Library/Caches/com.tinyspeck.slackmacgap.ShipIt`
- `~/.cache/solargraph`
- `~/.npm/_cacache`
- `~/.yarn/berry/cache`
- `~/.cache/uv`
- `~/Library/Logs/browser-monitor` (old diagnostic logs and stack samples; no backup)

Then it runs `HOMEBREW_NO_AUTO_UPDATE=1 brew cleanup -s` when Homebrew is installed.

At the end, it prints what was removed, approximate disk space freed, and manual follow-ups:

- Codex runtime cache skipped while Codex may be running: `~/.cache/codex-runtimes`
- Telegram local media/cache should be cleaned from Telegram settings.
- Old asdf runtimes should be reviewed with `asdf list` and removed with `asdf uninstall <plugin> <version>`.

It intentionally does **not** remove Android emulators/SDKs, browser profiles, Slack data, Telegram data, Codex runtime cache, asdf runtimes, or whole app support folders.

#### Additional inspection after cleanup

Check these areas read-only and report existing candidates with their sizes.
Do not automatically delete anything beyond the script's existing cleanup list.

1. Inspect first-level disk usage under `$HOME`, `~/Library`, `/Applications`,
   and `/opt/homebrew`. Drill into the largest local folders and look for files
   over 500 MiB. Do not follow symlinks or scan mounted/cloud-backed storage.
   Report permission-limited areas rather than claiming full coverage.
2. Check overlooked caches: `~/Library/Caches/Yarn`, `~/.npm/_npx`,
   `~/Library/Caches/node-gyp`, `~/Library/Caches/pnpm`,
   `~/.cache/selenium`, `~/.cache/ranger`, and
   `~/.config/xnviewmp/Thumb.db`. Explain that rebuilding or downloading may be
   needed; require affected tools/apps to be closed before any approved cleanup.
3. Browser-monitor diagnostics are already included in the standard cleanup
   above by user request. Do not archive them or retain recovery copies. Do not
   print private log contents. The monitor must be stopped before cleanup.
4. Check retained versions under `~/.codex/packages/app-server-daemon/releases`
   and `~/.local/share/claude/versions`. Compare with each installation's current
   symlink and check running processes before proposing removal. Never assume
   that every non-current version is unused. Report `~/.cache/codex-runtimes`
   separately; do not delete runtimes that may be in use.
5. List installed asdf versions and sizes. Inspect runtime declarations under
   `$DEV_ROOT/projects` when that directory exists; otherwise ask for the projects
   folder. Include hidden and ignored version files, while excluding dependency,
   generated, Git, and test-fixture directories. Check `.tool-versions`,
   `.ruby-version`, `.node-version`, `.nvmrc`, `.python-version`, Mise configs,
   Gemfile Ruby declarations, package.json engines, and pyproject.toml Python
   requirements. Read only relevant declarations, not surrounding secrets.
   Also check home/ancestor defaults and global tools installed in candidate
   runtimes. Report conflicting declarations. Distinguish "no declaration found"
   from "unused"; preserve the runtime running this agent. Use
   `asdf uninstall <plugin> <version>` only after approval of exact versions.
6. Check `~/.android/avd`, `~/Library/Android/sdk`, and Android Studio separately.
   Explain that deleting an emulator loses its apps/local data but leaves Studio
   and the SDK usable; another emulator or a physical device is then needed.
   Require separate approval for emulator, SDK, or application removal.
7. Report old recovery copies such as `~/.pi-backups`, `~/.pi/agent_bkp`, and
   `~/.dots-public-history-rewrite-backup-*`. Do not treat age or a backup-like
   name as permission to delete. Ask before creating or retaining recovery
   copies on another disk; follow standing state-change safety rules.
8. Check Homebrew's Cellar for multiple installed formula versions and report
   large applications the user might no longer use. Treat PostgreSQL directories
   under `/opt/homebrew/var` as database content, not package leftovers; keep
   them unless the user explicitly approves removal of the specific data.

Summarize rebuildable caches separately from diagnostics, app/runtime versions,
backups, and user/database data. Ask for approval of specific paths or versions
before additional cleanup. After approved removals, verify the targets are gone,
required apps/runtimes remain, and report current free space. This inspection
must not install tools, update packages, or create caches merely to inspect them.

### davinci-kill

Force-quit stuck DaVinci Resolve app processes.

Run:

```bash
~/.ai/skills-shared/misc-helper/scripts/misc-helper davinci-kill
```

The script:

- finds only the Resolve app executable and its bundled IOXPC helper by exact app paths;
- sends SIGTERM first;
- sends SIGKILL only to remaining matching processes;
- verifies no matching Resolve app processes remain.
