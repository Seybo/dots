---
name: dots-check
description: Scan dotfiles changes for secrets or sensitive data before publishing. Uses Ruby, git diffs, regexes, and entropy heuristics. Defaults to staged changes, then unstaged changes, then the last commit; supports full, untracked, and last-N-commit scans.
---

# Dots Check

A lightweight secret/sensitive info scanner for your dotfiles. Designed for use with pi / Codex / Claude Code via the Agent Skills standard.

## Setup

Requires `git`, `ruby` (3.x recommended). No extra gems.

This skill is repo-specific and lives in `.dots` at `.agents/skills/dots-check`.

No extra repo-detection guard is needed: if this skill is available, you're already in the right context.

## Usage

```bash
# Default: scan staged changes; if none, scan unstaged changes; if none, scan the last commit
./.agents/skills/dots-check/scripts/scan.rb

# Scan all tracked files
./.agents/skills/dots-check/scripts/scan.rb --all

# Scan unstaged tracked changes, ignoring staged changes and HEAD fallback
./.agents/skills/dots-check/scripts/scan.rb --unstaged

# Include untracked files (text only)
./.agents/skills/dots-check/scripts/scan.rb --untracked

# Scan unstaged tracked changes plus untracked files
./.agents/skills/dots-check/scripts/scan.rb --unstaged --untracked

# Filter to a glob
./.agents/skills/dots-check/scripts/scan.rb --path 'home/**/config/**'

# Scan changed lines in the last N commits
./.agents/skills/dots-check/scripts/scan.rb --last-commits 5
# Short alias
./.agents/skills/dots-check/scripts/scan.rb --last 5
```

## Invocation

There is exactly one command-style invocation for this skill:

- `/skill:dots-check`

In pi, when the user types `/skill:dots-check`, the agent may receive this `SKILL.md` content as a `<skill name="dots-check" ...>` block instead of seeing the raw slash command in the conversation. **That skill block means the skill was invoked.**

When this skill is invoked without a commit count, immediately run the default scan:

```bash
./.agents/skills/dots-check/scripts/scan.rb
```

If the user invokes or asks for dots-check with a last-commit count (for example, "last 5 commits"), immediately run:

```bash
./.agents/skills/dots-check/scripts/scan.rb --last-commits 5
```

Do not ask the user to type `/skill:dots-check` again. Do not explain how to invoke it. Do not wait for confirmation. Treat the invocation and/or the received skill block as an execution request.

Exit codes:
- `0` = no findings
- `1` = findings present
- `2` = usage error or fatal error

## Maintenance / TDD

When changing this skill, especially `scripts/scan.rb`:

1. Read the existing specs in `.agents/skills/dots-check/spec/`.
2. For behavior changes, add or update a failing spec first.
3. Run the spec and confirm the new/changed spec fails for the expected reason.
4. Implement the change.
5. Run the full spec suite:

   ```bash
   ruby .agents/skills/dots-check/spec/scan_spec.rb
   ```

6. Report the spec result when finished.

Do not report a scanner behavior change as complete unless the relevant spec was added/updated and the full spec suite passes.

## What it checks (MVP)
- High-signal token patterns (AWS, GitHub, Slack, Stripe, Twilio, Google API, OpenAI/Anthropic/etc keys, Hugging Face, JWT-ish, age secret keys, PEM blocks)
- Entropy heuristic for long random-looking strings (base58/64-ish) of length 32-128
- Skips binaries and files >1MB

## Extending later
- Add allowlists/skip-globs via config
- Add optional `gitleaks` / `detect-secrets` runners
- Add private domain/email checks

## Notes
- Default behavior is: scan staged changes; if there are none, scan unstaged changes; if there are none, scan `HEAD`.
- `--unstaged` scans only unstaged tracked changes, ignoring staged changes and avoiding the `HEAD` fallback. Combine it with `--untracked` to scan the whole uncommitted working tree.
- `--last-commits N` / `--last N` scans changed lines in each of the last `N` commits; it can be combined with `--path`, but not with `--all`, `--unstaged`, or `--untracked`.
- Keep output short to save model tokens. The scanner redacts matched secrets, absolute local user/volume paths, and truncates snippets.
- The scanner prints the files it checks before reporting findings.
- False positives happen; prefer auditing each finding rather than suppressing by default.
- The script resolves the git repo root itself, so it does not depend on `STOW_DIR` or the caller's current directory.
