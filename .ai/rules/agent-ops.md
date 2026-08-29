# Agent operating rules

Language- and project-neutral rules for all agents unless a project's local instructions override them.

## State-change safety

- Perform state-changing work only when the current explicit request or invoked skill authorizes it. Planning, grilling, review, and explanation workflows are read-only unless they explicitly say otherwise.
- Before moving, replacing, or deleting anything, identify state that version control cannot restore. If any exists, stop until it has a verified backup outside the affected paths.
- Inspection must not create or mutate the thing being inspected. Verify existence first and use read-only modes.

## Agent temporary files

- Put agent-owned temporary files in `agents_tmp/` at the active repository root instead of the operating system's temporary directory.
- Never stage or commit `agents_tmp/`.

## Git safety

- Never mutate git history, branches, tags, stashes, remotes, or commit state without explicit user approval for that exact action. This includes `commit`, `commit --amend`, `reset`, `rebase`, `merge`, `cherry-pick`, `revert`, `switch`/`checkout` that changes branches, branch create/delete/rename, tag create/delete, stash create/apply/pop/drop, force-push, and remote changes.
- Reading git state is allowed: `status`, `diff`, `log`, `show`, `branch --show-current`, and similar read-only commands.
- Staging files (`git add`) is also a git state mutation. Ask first unless the user explicitly asked to commit or prepare a commit.
- If approval is ambiguous, stop and ask.

### Commit subjects

- Use `<area>: <change>`. For a specific named component, use `<area>: <component>. <Change>`.
- Add the component only when it names a concrete skill, plugin, extension, or subsystem. Omit it when it merely repeats the area or subject.
- Keep the change concise and imperative. Example: `ai: autoimplement. Require explicit super-review policy`.

## Tmux process and layout safety

- Never run a tmux command or command sequence that terminates, replaces, respawns, recreates, resets, or closes an existing pane, window, session, shell, or pane process. This prohibition includes `respawn-pane`, `respawn-window`, `kill-pane`, `kill-window`, and `kill-session`, plus any command, option, signal, or workaround with an equivalent effect.
- Never replace a pane's shell with Pi or another interactive application, including through `exec`, a tmux direct-command argument, or any equivalent process replacement. Interactive applications must remain child processes of the pane's existing shell so exiting them returns to that shell.
- Do not create, split, move, join, swap, or break tmux panes/windows unless the user explicitly requested that exact layout change.
- Keep long-lived participant panes and Pi sessions in their normal working directory. When a workflow supplies an authoritative project path, target it explicitly with absolute file paths, `git -C`, or a per-command `cd`; do not change the pane's cwd or restart Pi. If a workflow truly requires shell setup, send ordinary commands only to an idle shell. If an idle shell is unavailable, stop and ask the operator; do not force, restart, or replace its current process.

## Autofix Work Cycle messages

- When the complete user message matches the case-sensitive pattern `^AutoFixCycle [0-9]+$`, immediately read and follow `~/.ai/skills-shared/autowork/autofix/app/prompts/work_cycle.md` using the supplied Work Cycle ID.
- Do not trigger the Autofix participant protocol when the message contains any other text or uses different capitalization.

## Autoimplement Work Cycle messages

- When the complete user message matches the case-sensitive pattern `^AutoImplementCycle [0-9]+$`, immediately read and follow `~/.ai/skills-shared/autowork/autoimplement/app/prompts/work_cycle.md` using the supplied Work Cycle ID.
- Do not trigger the Autoimplement participant protocol when the message contains any other text or uses different capitalization.

## Review state assumptions

- An unmerged PR's intermediate state is not a compatibility contract. Do not require compatibility for temporary commits, filenames, schemas, or behavior that never shipped; review the final branch against the merge base and deployed state.
- Do not treat a compatibility issue based only on existing database state as a finding until the operator confirms that the affected database exists and matters. Ask how that state should be handled before proposing migration, cleanup, or compatibility work.
- Apply the causal-proof, exploratory-candidate, and **Needs investigation** rules in `development-principles.md` before surfacing an actionable finding or using a concern to justify code changes.
- Do not add uncalled public options, provider capabilities, abstractions, or tests for anticipated use. Before accepting new API surface, identify the production caller and acceptance criterion; otherwise remove it or record it as explicitly deferred tech debt.

## Dotfiles stow safety

- In the dotfiles repo, never manually create symlinks from `~/.dots` into `$HOME`. Dotfile linking must go through the user's `stow_check` dry-run and `stow_do` apply commands.
- If `stow_check` reports a conflict, stop and explain the conflict. Do not work around Stow by running `ln -s`, replacing targets manually, or using `stow --adopt` unless the user explicitly approves that exact action.

## GitHub PR reviews

- When the user links a specific GitHub PR review URL or review ID, fetch it directly with `gh api repos/<owner>/<repo>/pulls/<pr>/reviews/<review_id>` (review body) and `gh api repos/<owner>/<repo>/pulls/<pr>/reviews/<review_id>/comments` (inline comments). Web fetch and plain `gh pr view` can miss inline review comments.
