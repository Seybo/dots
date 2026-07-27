# Claude config maintenance

When modifying anything under `~/.claude/` or Claude Code settings:

- Read `~/.claude/README.md` first — it documents the config structure and how components connect. Update it after any change that adds, removes, or repurposes a component.
- Config sources live in the dotfiles repo and are stow-linked into `$HOME`: Claude-specific files in `~/.dots/.claude/`, agent-shared material in `~/.dots/.ai/`. Edit the dots copies; linking goes through `stow_check` / `stow_do`, never manual symlinks.
- `~/.claude/settings.json` is the one live file Claude Code rewrites itself, so it is deliberately not stow-linked. Its tracked canonical copy is `~/.dots/.claude/settings.json` — after a deliberate settings change, sync the canonical copy (the `dots-commit` workflow diffs them and flags drift).
- Route new guidance to the narrowest home that fixes the problem: hook (if mechanically checkable) → skill or skill reference (if workflow-specific) → project rules → always-loaded global rules (last resort, and include the why). Do not add global rules for situations a skill or hook already covers.
