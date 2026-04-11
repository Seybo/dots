---
name: dots-check
description: Scan dotfiles changes for secrets or sensitive data before publishing. Uses Ruby, git diffs, regexes, and entropy heuristics. Defaults to changed files; supports full and untracked scans.
---

# Dots Check

A lightweight secret/sensitive info scanner for your dotfiles. Designed for use with pi / Codex / Claude Code via the Agent Skills standard.

## Setup

Requires `git`, `ruby` (3.x recommended). No extra gems.

Place this skill where your harness can discover it, e.g. stow to `~/.agents/skills/dots-check` and add `~/.agents/skills` to your skills paths.

### Agent guard (important)
- Before running anything else, execute **only** `pwd` and compare to `$STOW_DIR`.
- If `pwd` != `$STOW_DIR`, **stop immediately**. Do not run `ls`, `git`, or the scanner.
- If `STOW_DIR` is unset, **stop immediately**.
- Run the scanner only when `pwd` == `$STOW_DIR`.

## Usage

```bash
# Default: scan staged changes; if none, scans working-tree changes vs HEAD
./scripts/scan.rb

# Scan all tracked files
./scripts/scan.rb --all

# Include untracked files (text only)
./scripts/scan.rb --untracked

# Filter to a glob
./scripts/scan.rb --path 'home/**/config/**'
```

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
- False positives happen; prefer auditing each finding rather than suppressing by default.
- Requires `STOW_DIR` to be set and the current working directory to equal that path (`pwd` must be `STOW_DIR`); otherwise the script exits with an error.
