# Dots repo context

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
- Before using bash patterns that may be restricted, check `.agents/permission.settings.json` mentally/explicitly and avoid commands matching the `deny` list when practical.
- In particular, avoid `find ... -exec`, `find ... -delete`, `find ... -ok`, and `find ... -execdir`; prefer separate `find`, `ls`, `rg`, or shell-safe follow-up commands.
