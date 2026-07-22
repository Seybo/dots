---
name: misc-helper
description: Run small personal helper utilities from one command namespace. Command-only skill. Invoke via /misc-helper <helper>, currently supports davinci-kill, cache-clean, and tmux-bar-reset.
allowed-tools:
  - "bash(/Users/inseybo/.ai/skills-shared/misc-helper/scripts/misc-helper *)"
disable-model-invocation: true
---

# Misc Helper

This is a command-only skill for small personal helper utilities that do not deserve separate skills.

## Invocation

Use only:

```text
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
/Users/inseybo/.ai/skills-shared/misc-helper/scripts/misc-helper tmux-bar-reset
```

The script clears tmux window/global options used by the agent attention bar and stops `agent-attention-notify --pane` watcher processes.

### cache-clean

Remove known-safe local cache/generated-data folders from this Mac.

Run:

```bash
/Users/inseybo/.ai/skills-shared/misc-helper/scripts/misc-helper cache-clean
```

The script first asks the user to type `CLOSED` to confirm affected apps are closed.

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

Then it runs `HOMEBREW_NO_AUTO_UPDATE=1 brew cleanup -s` when Homebrew is installed.

At the end, it prints what was removed, approximate disk space freed, and manual follow-ups:

- Codex runtime cache skipped while Codex may be running: `~/.cache/codex-runtimes`
- Telegram local media/cache should be cleaned from Telegram settings.
- Old asdf runtimes should be reviewed with `asdf list` and removed with `asdf uninstall <plugin> <version>`.

It intentionally does **not** remove Android emulators/SDKs, browser profiles, Slack data, Telegram data, Codex runtime cache, asdf runtimes, or whole app support folders.

### davinci-kill

Force-quit stuck DaVinci Resolve app processes.

Run:

```bash
/Users/inseybo/.ai/skills-shared/misc-helper/scripts/misc-helper davinci-kill
```

The script:

- finds only the Resolve app executable and its bundled IOXPC helper by exact app paths;
- sends SIGTERM first;
- sends SIGKILL only to remaining matching processes;
- verifies no matching Resolve app processes remain.
