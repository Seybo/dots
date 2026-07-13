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
- Hammerspoon config for opacity-controlled alerts: `~/.dots/.hammerspoon/init.lua`

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

## Local gotchas

- `terminal-notifier` can log/list notifications as delivered without showing visible banners in this environment. `osascript display notification` produced visible non-modal banners, so `monit-notify` uses that path.
- `monit-cpu-alerts procmatch` can fail when Monit has no default control file because it does not pass the runtime `-c` path; use `ps` to sanity-check scan regexes in that case.
- `monit-notify` prefers a custom Hammerspoon drawing and falls back to `osascript display notification` when `hs`/Hammerspoon is unavailable.
- Current notification styling/text behavior lives in `~/.dots/.hammerspoon/init.lua`; consult that file instead of duplicating details here.
- `hs -c` runs code in the Hammerspoon app process, so environment variables assigned to the `hs` CLI are not visible through `os.getenv` in the evaluated Lua. Pass dynamic notification text another way, such as temp files.

## Official sources

- Monit manual: `https://mmonit.com/monit/documentation/monit.html`
- Monit downloads: `https://mmonit.com/monit/`
