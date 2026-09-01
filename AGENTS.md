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

- For Ruby packages in this dots repo, run Bundler commands from the directory containing the intended `Gemfile`; prefer the relevant package's `bin/check` when it exists.
- When a request refers to "dev-env refs" without a path, treat it as referring to `refs/dev-env`.
- Be explicit about file paths when reading or editing files there.
- Summarize which files were read or changed.

## Tool permissions

- For permission prompts / allowlist changes, read `refs/dev-env/agent-permissions.md` or use the shared `agent-permissions` skill. Default: update both Claude Code and Pi permissions unless the user explicitly scopes to one.
- For browser CPU spike investigations from this repo, use the exact approved wrapper commands: `/Users/inseybo/.dots/no_stow/bin/browser-spike-investigate brave` or `/Users/inseybo/.dots/no_stow/bin/browser-spike-investigate chrome`. Do not run ad-hoc `ps`/`sample`/`lsof`/`awk` investigation chains unless the wrapper is insufficient and the user approves.
- Pi's Repository mode allows ordinary commands and tools by default but prompts for explicit high-impact operations. Unattended mode uses the same policy but blocks approval-required operations immediately. Prefer path-aware `read`, `edit`, and `write` when they express the work clearly and preserve startup ignored-file and Git-metadata checks.
- Literal `rm` and plain `rmdir` targets that resolve inside the repository are allowed. Dynamic, escaping, and parent-removing `rmdir` targets require approval, and are blocked in Unattended mode.

### Shell command safety

- When processing dynamically discovered paths, first list the paths, then run the follow-up command on those literal paths in a separate tool call.
- Avoid combining discovery with execution, deletion, or file-writing when the work can be expressed safely as two operations.
- For `find`, approval-required examples include `-exec`, `-execdir`, `-ok`, `-okdir`, `-delete`, `-fprint`, `-fprint0`, `-fprintf`, and `-fls`.

### Preferred command shapes

Prefer simple read-only shapes when they express the same work.

- Avoid `find DIR -maxdepth 1 -type d -exec basename {} \; | sort`.
  - Prefer `ls -1 DIR | sort` when first-level non-hidden names are enough.
  - Prefer `ls -1A DIR | sort` when hidden names should be included too.
  - Prefer `find DIR -maxdepth 1 -type d -print | xargs -n1 basename | sort` when the command specifically needs directories only.
- Avoid `cat $(find app -name 'foo.rb' | head -1)`.
  - Prefer `find app -name 'foo.rb' -print -quit`, then read the discovered path with the read tool.
  - Prefer `rg --files app | rg 'foo\.rb$'` when filename search is enough, then use the read tool.
- Avoid cosmetic `sed` cleanup when the agent can read raw paths directly.
- Avoid multiline bash payloads; use one-line commands split with `;` / `&&` only when each segment is safe, or use separate tool calls.
