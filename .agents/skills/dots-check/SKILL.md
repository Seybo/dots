---
name: dots-check
description: Scan dotfiles changes for secrets or sensitive data before publishing. Uses Ruby, git diffs, regexes, and entropy heuristics. Defaults to changed files; supports full and untracked scans.
---

# Dots Check

A lightweight secret/sensitive info scanner for your dotfiles. Designed for use with pi / Codex / Claude Code via the Agent Skills standard.

## Setup

Requires `git`, `ruby` (3.x recommended). No extra gems.

This skill is repo-specific and lives in `.dots` at `.agents/skills/dots-check`.

No extra repo-detection guard is needed: if this skill is available, you're already in the right context.

## Usage

```bash
# Default: scan staged changes; if none, scans working-tree changes vs HEAD
./.agents/skills/dots-check/scripts/scan.rb

# Scan all tracked files
./.agents/skills/dots-check/scripts/scan.rb --all

# Include untracked files (text only)
./.agents/skills/dots-check/scripts/scan.rb --untracked

# Filter to a glob
./.agents/skills/dots-check/scripts/scan.rb --path 'home/**/config/**'
```

## Bare invocation behavior

If the user invokes `dots-check` by name without additional options or qualifiers, immediately run the default scan:

```bash
./.agents/skills/dots-check/scripts/scan.rb
```

Interpret bare invocation as an execution request, not as a request for explanation or confirmation.

Examples:
- `dots-check` → run default scan
- `/dots-check` → run default scan
- `use dots-check` → run default scan
- `run dots-check on everything` → run `./.agents/skills/dots-check/scripts/scan.rb --all`

Only do not execute immediately if the user is clearly asking about the skill itself, for example:
- `what does dots-check do?`
- `how does dots-check work?`

Exit codes:
- `0` = no findings
- `1` = findings present
- `2` = usage error or fatal error

## What it checks (MVP)
- High-signal token patterns (AWS, GitHub, Slack, Stripe, Twilio, Google API, OpenAI/Anthropic/etc keys, Hugging Face, JWT-ish, PEM blocks)
- Entropy heuristic for long random-looking strings (base58/64-ish) of length 32-128
- Skips binaries and files >1MB

## Extending later
- Add allowlists/skip-globs via config
- Add optional `gitleaks` / `detect-secrets` runners
- Add private domain/email checks

## Notes
- Keep output short to save model tokens. The scanner truncates snippets.
- The scanner prints the files it checks before reporting findings.
- False positives happen; prefer auditing each finding rather than suppressing by default.
- The script resolves the git repo root itself, so it does not depend on `STOW_DIR` or the caller's current directory.
