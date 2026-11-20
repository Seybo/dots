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

Inspect disk usage first, present one cleanup report, then let the user choose
what to remove. Cover the `dev`, `other`, and `vault` volumes sharing an APFS
container, as well as the existing home-directory/application cleanup areas.
Do not delete anything or run the cleanup script before presenting the report
and receiving the user's cleanup choice.

The agent performs inspection and approved follow-ups. The existing script is
only the standard fixed-list cleanup executor, not the full skill workflow.

#### Standard cleanup scope

Keep this existing cleanup option available after inspection. The script removes
only these paths:

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
- `~/Library/Caches/typescript`
- `~/Library/Caches/com.tinyspeck.slackmacgap.ShipIt`
- `~/.cache/solargraph`
- `~/.npm/_cacache`
- `~/.yarn/berry/cache`
- `~/.cache/uv`
- `~/Library/Logs/browser-monitor` (old diagnostic logs and stack samples; no backup)

After removing those paths, the script runs
`HOMEBREW_NO_AUTO_UPDATE=1 brew cleanup -s` when Homebrew is installed.
Include both the fixed paths and Homebrew cleanup in the report's standard
cleanup option.

At the end, it prints what was removed, approximate disk space freed, and manual follow-ups:

- Codex runtime cache skipped while Codex may be running: `~/.cache/codex-runtimes`
- Telegram local media/cache should be cleaned from Telegram settings.
- Old asdf runtimes should be reviewed with `asdf list` and removed with `asdf uninstall <plugin> <version>`.

It intentionally does **not** remove Android emulators/SDKs, browser profiles, Slack data, Telegram data, Codex runtime cache, asdf runtimes, or whole app support folders.

#### Cleanup exclusions

- `~/Library/Caches/ms-playwright`: preserve installed Playwright browser
  binaries. Removing them breaks browser tests until they are reinstalled;
  do not include this directory in standard cleanup.

- `~/.config/xnviewmp/Thumb.db`: preserve this file. Do not propose it as a
  cleanup candidate or delete it, including during additional cleanup.

#### Phase 1: Read-only inspection and report

Resolve the actual mount points and APFS container membership of `dev`, `other`,
and `vault` using read-only storage metadata, such as `diskutil apfs list` and
`diskutil info`. Do not assume a volume name is its mount point or that `$HOME`
shares their container. Record the container's free space once, not the sum of
per-volume available-space figures. Report any other containers separately.
If a target volume is absent, locked, or unmounted, report that limitation;
do not mount or unlock it as part of inspection.

Inspect first-level usage on all three available volumes, then drill into the
largest local folders. Avoid traversing the same paths twice when inspection
roots overlap. Do not follow symlinks, cross into unrelated mounted storage,
or scan cloud-backed content. Report permission-limited and skipped areas
without claiming full coverage. List discovered paths before issuing follow-up
commands on those literal paths.

For development projects, look for large caches, dependency folders, and
generated/build output. Report these as candidates, not automatically disposable
files: ignored or untracked status does not prove data is safe to delete.
Distinguish source code and local changes from rebuildable data, databases,
diagnostics, runtimes, backups, and other user data. Explain deletion consequences
and any rebuilding or downloading needed. Respect standing backup requirements
for state version control cannot restore.

Measure existing paths in the standard cleanup list above, then check these
existing areas read-only and report candidates with their sizes. Do not run
cleanup, install tools, update packages, or create caches merely to inspect them.

1. Inspect first-level disk usage under `$HOME`, `~/Library`, `/Applications`,
   and `/opt/homebrew`. Drill into the largest local folders and look for files
   over 500 MiB. Do not follow symlinks, cross into unrelated mounts, or scan
   cloud-backed storage.
   Report permission-limited areas rather than claiming full coverage.
2. Check overlooked caches: `~/Library/Caches/Yarn`, `~/.npm/_npx`,
   `~/Library/Caches/node-gyp`, `~/Library/Caches/pnpm`,
   `~/.cache/selenium`, and `~/.cache/ranger`. Explain that rebuilding or downloading may be
   needed; require affected tools/apps to be closed before any approved cleanup.
3. Browser-monitor diagnostics are included in the standard cleanup option
   above by user request, but have not been deleted during inspection. Do not
   archive them or retain recovery copies. Do not print private log contents.
   The monitor must be stopped before cleanup.
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

Present one report before any deletion. Identify each candidate's path, size,
volume, consequences, and whether it belongs to the standard cleanup list or
requires separate approval. Summarize rebuildable caches separately from
diagnostics, app/runtime versions, backups, and user/database data. Show shared
container free space once and clearly identify inspection limitations.

#### Phase 2: Approved cleanup and verification

After the report, offer the existing standard cleanup and the specific additional
candidates. Inspection alone does not authorize cleanup. Wait for the user's
choice; require approval of exact paths or versions for additional removals.
Check affected tools/processes and require them to be stopped when necessary.
Do not stop processes automatically.

Only if the user chooses standard cleanup, run:

```bash
~/.ai/skills-shared/misc-helper/scripts/misc-helper cache-clean
```

Retain the script's `CLOSED` confirmation that affected apps are closed and
browser-cpu-monitor is stopped. It warns that browser-monitor diagnostics will
be deleted without a backup. Do not bypass or supply that confirmation on the
user's behalf. The script may clear home-directory caches on a different
container; make that distinction clear in the report.

Perform only approved additional removals, respecting the safety rules above.
After cleanup, verify the approved targets are gone and required apps/runtimes
remain. Re-read storage metadata and report the shared APFS container's free
space once. Keep other containers' figures separate; do not use the script's
home-volume free-space delta as the shared container's reclaimed space unless
you verified they belong to the same container. Separate removed targets from
skipped or failed removals in the final report.

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
