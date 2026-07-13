# monit

## Local sources

- `man monit`
- `monit --help`
- `monit -h`
- `monit -V`
- Local setup guide: `~/.dots/no_stow/monit/README.md`
- Helper CLI help: `~/.dots/no_stow/bin/monit-cpu-alerts help`

## Local configs

- Source template: `~/.dots/no_stow/monit/monitrc`
- Source include template: `~/.dots/no_stow/monit/conf.d/high-cpu.monit`
- Source LaunchAgent template: `~/.dots/no_stow/monit/LaunchAgents/local.monit.plist`
- Helper CLI: `~/.dots/no_stow/bin/monit-cpu-alerts`
- Multi-process scanner: `~/.dots/no_stow/bin/monit-cpu-scan`
- Notification script: `~/.dots/no_stow/bin/monit-notify`

## Runtime paths

- Runtime config: `~/Library/Application Support/monit/monitrc`
- Runtime local checks: `~/Library/Application Support/monit/conf.d/high-cpu-local.monit`
- Runtime state/event files: `~/Library/Application Support/monit/`
- Generated check-program wrappers: `~/.local/state/monit/programs/`
- User LaunchAgent: `~/Library/LaunchAgents/local.monit.plist`
- Logs: `~/Library/Logs/monit.log`, `~/Library/Logs/monit-notify.log`, `~/Library/Logs/monit-cpu-scan.log`, `~/Library/Logs/monit-launchd.out.log`, `~/Library/Logs/monit-launchd.err.log`

## Local workflow

- Install/render runtime config: `~/.dots/no_stow/bin/monit-cpu-alerts install`
- Add unique-process CPU rule: `~/.dots/no_stow/bin/monit-cpu-alerts add <name> <regex> [pct] [sec] [cpu|total_cpu]`
- Add multi-process CPU scan: `~/.dots/no_stow/bin/monit-cpu-alerts add-scan <name> <regex> [pct] [sec] [cooldown_sec]`
- Validate/reload/status: `~/.dots/no_stow/bin/monit-cpu-alerts test|reload|status|paths|edit`
- Start/stop LaunchAgent: `~/.dots/no_stow/bin/monit-cpu-alerts load|unload`
- Current Zellij monitor is a scan rule: `zellij`, regex `(^|/)zellij( |$)`, threshold `30%`, duration `30s`, cooldown `300s`.
- Current tmux monitor is a scan rule: `tmux`, regex `(^|/)tmux( |$)`, threshold `30%`, duration `30s`, cooldown `300s`.
- Current Pi monitor is a scan rule: `pi`, regex `(^|/)pi( |$)`, threshold `15%`, duration `10s`, cooldown `300s`.
- Current Brave monitor is a scan rule: `brave`, regex `Brave Browser`, threshold `5%`, duration `15s`, cooldown `300s`.
- Current Chrome monitor is a scan rule: `chrome`, regex `Google Chrome`, threshold `5%`, duration `15s`, cooldown `300s`.

## Local gotchas

- `terminal-notifier` can log/list notifications as delivered without showing visible banners in this environment. `osascript display notification` produced visible non-modal banners, so `monit-notify` uses that path.
- `monit-cpu-alerts procmatch` can fail when Monit has no default control file because it does not pass the runtime `-c` path; use `ps` to sanity-check scan regexes in that case.
- Current notification path uses `osascript display notification`; neither that local script nor `terminal-notifier` help exposes opacity controls, so opacity would require a custom overlay/notifier instead of native macOS notifications.
- For opacity-controlled alerts, Hammerspoon `hs.alert` is a practical replacement path: its style supports `fillColor`/`textColor` alpha values and fade durations.

## Official sources

- Monit manual: `https://mmonit.com/monit/documentation/monit.html`
- Monit downloads: `https://mmonit.com/monit/`
