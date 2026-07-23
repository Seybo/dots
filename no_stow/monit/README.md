# Monit CPU alerts

Free macOS high-CPU notifications using Monit plus custom Hammerspoon opacity-controlled alerts, with `osascript` notification fallback.

## Why this setup

Monit is a good fit for rules such as "process matching this regex uses more than 30% CPU for 60 seconds". The notifier script prefers a custom Hammerspoon drawing for top-right opacity-controlled floating alerts and falls back to non-modal macOS notification banners via `osascript display notification`. Hammerspoon reads `~/.dots/themes/active/ghostty` at notification time, uses the active terminal `background` at 90% opacity, chooses black or white text by luminance, estimates alert height from wrapped text with min/max bounds, and renders alerts as a compact service/match plus CPU-threshold summary.

This setup differs slightly from generic snippets:

- LaunchAgent runs `monit -I -c ...` so launchd supervises a foreground Monit process.
- The Monit runtime config is copied to `~/Library/Application Support/monit` with chmod `600`, because Monit rejects loose config-file permissions.
- Process rules are runtime-local by default so permissions stay valid.
- Use `add` for a unique process. Use `add-scan` when many processes share the same name, such as tmux processes.
- Generated check-program wrappers live in `~/.local/state/monit/programs` because Monit does not reliably accept `check program` paths with spaces.

## Install

```sh
brew install monit
brew install --cask hammerspoon
~/.dots/no_stow/bin/monit-cpu-alerts install
```

## Add a process rule

For a unique process, use Monit's native process resource check:

```sh
~/.dots/no_stow/bin/monit-cpu-alerts add ruby-lsp 'ruby-lsp' 30 60 total_cpu
```

Arguments:

1. Monit service name, e.g. `ruby-lsp`
2. Monit process regex, e.g. `ruby-lsp`
3. CPU percent, default `30`
4. Seconds over threshold, default `60`
5. CPU kind: `cpu` for the matched process only, or `total_cpu` for process plus children

With the default 5-second poll, 60 seconds becomes 12 consecutive Monit cycles.

Check the regex before relying on it:

```sh
~/.dots/no_stow/bin/monit-cpu-alerts procmatch 'ruby-lsp'
```

## Add a multi-process scan rule

For apps that spawn multiple processes with the same name, use `add-scan`. This scans all matching processes and notifies when any one PID stays above the threshold long enough.

```sh
~/.dots/no_stow/bin/monit-cpu-alerts add-scan tmux '(^|/)tmux( |$)' 30 30 300
```

Arguments:

1. Monit program check name, e.g. `tmux`
2. process regex matched against executable path/name and command args
3. CPU percent, default `30`
4. seconds over threshold, default `60`
5. notification cooldown seconds, default `300`

## Start at login

```sh
~/.dots/no_stow/bin/monit-cpu-alerts load
```

Stop it:

```sh
~/.dots/no_stow/bin/monit-cpu-alerts unload
```

After editing or adding rules while Monit is running:

```sh
~/.dots/no_stow/bin/monit-cpu-alerts reload
```

## Useful commands

```sh
~/.dots/no_stow/bin/monit-cpu-alerts test
~/.dots/no_stow/bin/monit-cpu-alerts status
~/.dots/no_stow/bin/monit-cpu-alerts edit
~/.dots/no_stow/bin/monit-cpu-alerts paths
```

Current configured monitors live in runtime files, not in this README:

```sh
~/.dots/no_stow/bin/monit-cpu-alerts status
~/.dots/no_stow/bin/monit-cpu-alerts paths
ls ~/.local/state/monit/programs
```

Logs:

- `~/Library/Logs/monit.log`
- `~/Library/Logs/monit-notify.log`
- `~/Library/Logs/monit-cpu-scan.log`
- `~/Library/Logs/monit-launchd.out.log`
- `~/Library/Logs/monit-launchd.err.log`
