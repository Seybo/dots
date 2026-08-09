# Task branch configuration (shared)

Single source of truth for branch setup metadata used by Taskit, Workit,
Autoimplement, and Autofix. Taskit and Workit must read this file completely
when creating, verifying, or recording a Task branch. Caller docs own only when
the rules run and how project/task/workspace identity is resolved.

## Config file

Store branch metadata at:

```text
<task-folder>/config.json
```

Use this exact section:

```json
{
  "branch": {
    "name": "<task-branch>",
    "original_base_ref": "<base-ref>",
    "original_base_commit_sha": "<full-base-SHA>",
    "active_base_ref": "<base-ref>",
    "active_base_commit_sha": "<full-base-SHA>"
  }
}
```

Preserve unrelated top-level sections. Require every branch value to be a
non-empty string. Reject conflicting existing branch config instead of
overwriting it.

Original base fields record branch creation and never change. Initialize active
fields to the same values. Only a later explicit successful rebase may update
active fields.

## Shortcut Task branch setup

Inputs supplied by the caller:

- canonical Task folder
- selected checkout
- generated Shortcut task branch name
- optional exact `base_ref`

Check the checkout's current branch and full `HEAD` SHA before branch creation.
Verify whether the generated task branch already exists.

### Existing task branch

If the generated branch exists but is not checked out, stop and ask before
switching. Never switch silently.

If complete branch config exists, validate it against the generated branch and
do not rewrite it. When an explicit `base_ref` is also supplied, resolve it and
verify it is an ancestor of `HEAD`; stop on failure.

If branch config is missing or incomplete, require explicit `--base <ref>`:

1. Require a clean worktree.
2. Fetch `origin`.
3. Resolve the supplied ref exactly with `git rev-parse <ref>^{commit}`.
4. Verify that resolved commit is an ancestor of `HEAD`.
5. Write original and active config from the exact ref and full resolved SHA.

Do not infer a missing base from `main`, `master`, merge-base, reflog, Git
upstream, a task ID, or any other source. Do not rebase during branch setup.

### New task branch with explicit base

1. Require a clean worktree.
2. Fetch `origin`.
3. Resolve the supplied ref exactly with `git rev-parse <ref>^{commit}`.
4. Create the branch without parent tracking:

   ```bash
   git -C <checkout> checkout --no-track -b <branch-name> <base-ref>
   ```

5. Write original and active config from the exact ref and full resolved SHA.

Do not rewrite the supplied ref. `--no-track` prevents a remote parent branch
from becoming the new task branch's Git upstream; parent ownership belongs in
Task config.

### New task branch with implicit base

Capture the current source branch name and full `HEAD` SHA. Inspect its
configured upstream:

- when the upstream resolves to the same SHA, select the exact upstream ref;
- otherwise select the exact local source branch.

Do not infer another remote ref. Create the task branch from current `HEAD`:

```bash
git -C <checkout> checkout -b <branch-name>
```

Write original and active config from the selected ref and captured source SHA.
Do not configure the new task branch to track its parent.

## Local Task setup

Taskit creates or converts the Task folder but does not record local Git
metadata. Workit records it immediately before planning and Autoimplement
initialization, after applying the shared protected-branch rules.

Local Tasks use the current branch as-is. Never infer, create, rename, or switch
a local branch. Record:

- `name`: current branch
- every original/active base ref/SHA: current full `HEAD` SHA

If branch config already exists, validate the configured branch and do not
rewrite original values. Preserve unrelated config sections. Local Tasks never
rebase.

## Reporting

After creating or repairing branch config, report the selected checkout, branch
name, base ref, full base SHA, and config path. Branch setup never pushes.
