# Monit CPU alerts

Free macOS high-CPU notifications using Monit plus `osascript` notification banners.

## Why this setup

Monit is a good fit for rules such as "process matching this regex uses more than 30% CPU for 60 seconds". The notifier script uses non-modal macOS notification banners via `osascript display notification`.

This setup differs slightly from generic snippets:

- LaunchAgent runs `monit -I -c ...` so launchd supervises a foreground Monit process.
- The Monit runtime config is copied to `~/Library/Application Support/monit` with chmod `600`, because Monit rejects loose config-file permissions.
- Process rules are runtime-local by default so permissions stay valid.
- Use `add` for a unique process. Use `add-scan` when many processes share the same name, such as Zellij sessions.
- Generated check-program wrappers live in `~/.local/state/monit/programs` because Monit does not reliably accept `check program` paths with spaces.

## Install

```sh
brew install monit
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
~/.dots/no_stow/bin/monit-cpu-alerts add-scan zellij '(^|/)zellij( |$)' 30 30 300
```

Arguments:

1. Monit program check name, e.g. `zellij`
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

Current local monitor:

- `zellij`: scan all matching `zellij` PIDs with regex `(^|/)zellij( |$)`; notify above `30%` CPU for `30s`, with `300s` per-PID cooldown.
- `pi`: scan all matching `pi` PIDs with regex `(^|/)pi( |$)`; notify above `15%` CPU for `10s`, with `300s` per-PID cooldown.

Logs:

- `~/Library/Logs/monit.log`
- `~/Library/Logs/monit-notify.log`
- `~/Library/Logs/monit-cpu-scan.log`
- `~/Library/Logs/monit-launchd.out.log`
- `~/Library/Logs/monit-launchd.err.log`
