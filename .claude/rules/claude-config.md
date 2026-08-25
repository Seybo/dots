# Claude config maintenance

When modifying anything under `~/.claude/` or Claude Code settings:

- Read `~/.claude/README.md` first — it documents the config structure and how components connect. Update it after any change that adds, removes, or repurposes a component.
- Config sources live in the dotfiles repo and are stow-linked into `$HOME`: Claude-specific files in `~/.dots/.claude/`, agent-shared material in `~/.dots/.ai/`. Edit the dots copies; linking goes through `stow_check` / `stow_do`, never manual symlinks.
- `~/.claude/settings.json` is the one live file Claude Code rewrites itself, so it is not stow-linked. Its ignored repo-local baseline is `~/.dots/.claude/settings.json`; `dots-commit` confirms live changes, updates the baseline, and scans it without committing it.
- Route new guidance to the narrowest home that fixes the problem: hook (if mechanically checkable) → skill or skill reference (if workflow-specific) → project rules → always-loaded global rules (last resort, and include the why). Do not add global rules for situations a skill or hook already covers.
