# Dots repo context

## Development style

- This is a personal local-dev dotfiles repo. Prefer the simplest solution that works now.
- KISS and YAGNI are primary rules here: do not build abstractions, generic frameworks, broad edge-case handling, or future-proofing unless the user asks for it or it is clearly needed in the near future.
- Implement the immediate workflow first. Add complexity later only after real usage shows it is needed.
- When a simple manual/local workflow is enough, choose it over automation.

## Path shorthands

- When I say "dev-env refs", I mean `refs/dev-env` in this repo.
- "read dev-env refs" means inspect files under `refs/dev-env`.
- "update dev-env refs" means modify documentation in `refs/dev-env`.
- Prefer starting by listing the directory and reading relevant Markdown or reference files in `refs/dev-env` before making changes.

## Working style

- When a request refers to "dev-env refs" without a path, treat it as referring to `refs/dev-env`.
- Be explicit about file paths when reading or editing files there.
- Summarize which files were read or changed.

## Tool permissions

- For permission prompts / allowlist changes, read `refs/dev-env/agent-permissions.md` or use the shared `agent-permissions` skill. Default: update both Claude Code and Pi permissions unless the user explicitly scopes to one.
- For browser CPU spike investigations from this repo, use the exact approved wrapper commands: `/Users/inseybo/.dots/no_stow/bin/browser-spike-investigate brave` or `/Users/inseybo/.dots/no_stow/bin/browser-spike-investigate chrome`. Do not run ad-hoc `ps`/`sample`/`lsof`/`awk` investigation chains unless the wrapper is insufficient and the user approves.
- Before using bash patterns that may be restricted, check `.agents/permission.settings.json` mentally/explicitly and avoid commands matching the `deny` list when practical.
- In particular, avoid `find ... -exec`, `find ... -delete`, `find ... -ok`, and `find ... -execdir`; prefer separate `find`, `ls`, `rg`, or shell-safe follow-up commands.

### Safe command substitutions

When a command would trigger avoidable permission prompts, prefer an already-safe read-only shape instead of requesting new permissions.

- Avoid `find DIR -maxdepth 1 -type d -exec basename {} \; | sort`.
  - Prefer `ls -1 DIR | sort` when first-level non-hidden names are enough.
  - Prefer `ls -1A DIR | sort` when hidden names should be included too.
  - Prefer `find DIR -maxdepth 1 -type d -print | xargs -n1 basename | sort` when the command specifically needs directories only.
- Avoid `cat $(find app -name 'foo.rb' | head -1)`.
  - Prefer `find app -name 'foo.rb' -print -quit`, then read the discovered path with the read tool.
  - Prefer `rg --files app | rg 'foo\.rb$'` when filename search is enough, then use the read tool.
- Avoid cosmetic `sed` cleanup when the agent can read raw paths directly.
- Avoid multiline bash payloads; use one-line commands split with `;` / `&&` only when each segment is safe, or use separate tool calls.
