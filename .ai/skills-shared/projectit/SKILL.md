---
name: projectit
description: >-
  Create an ordinal-workspace project for the task workflow. Creates its task
  root, first code workspace, Git repository, tmuxinator layout, registry
  entry, and active-project entry. Command-only skill. In Pi, invoke via
  /skill:projectit; /projectit is also accepted where that alias is exposed.
disable-model-invocation: true
---

# Projectit

This is a command-only skill.

## Invocation

In Pi, use either:

```text
/skill:projectit help
/projectit help
/projectit <group> <name>
```

Examples:

```text
/projectit shaka p1
/projectit my p1
/projectit misc notes
```

Do not auto-use this skill from a general project-management request. Wait for the explicit slash command.

## What it does

`<group> <name>` creates a friendly task project key, a task root, and its required `1st` ordinal workspace:

```text
/projectit shaka p1

project key: shaka_p1
$DEV_ROOT/_tasks/shaka_p1/
$DEV_ROOT/projects/shaka/p1/1st/
```

Group mappings:

```text
my    -> project key my_<name>,    code root $DEV_ROOT/projects/my/<name>/
shaka -> project key shaka_<name>, code root $DEV_ROOT/projects/shaka/<name>/
misc  -> project key misc_<name>,  code root $DEV_ROOT/projects/misc/<name>/
```

It initializes the `1st` workspace as a Git repository, registers an `ordinal_workspaces` project in:

```text
~/.ai/skills-shared/components/projects.yml
```

and adds the workspace repo root to:

```text
~/.dots/refs/dev-env/active-projects.md
```

Additional workspaces use positive ordinals such as `2nd`, `7th`, and `28th`.
Tmux sessions use `<project-key><number>`.

## Instructions

1. **Parse command arguments:**
   - if the only argument is `help`, show this help text and stop
   - require exactly two tokens: `<group> <name>`
     - allowed groups: `my`, `shaka`, `misc`
     - build `<project>` as `<group>_<name>`
   - otherwise stop and show:
     ```text
     /projectit <group> <name>
     ```

2. **Validate the name:**
   - `<name>` must be one safe lowercase path segment matching `^[a-z][a-z0-9_-]*$`
   - do not allow whitespace, `/`, `.`, `..`, or shell metacharacters
   - do not create `env`; it is the dotfiles infrastructure project
   - if invalid, stop and ask for a lowercase name such as `p1`, `budget_app`, or `notes`

3. **Resolve paths:**
   - read and follow `~/.ai/skills-shared/components/task-resolution.md`
   - task root:
     ```text
     $DEV_ROOT/_tasks/<project>/
     ```
   - code root and required first workspace:
     ```text
     $DEV_ROOT/projects/my/<name>/1st/     # group my
     $DEV_ROOT/projects/shaka/<name>/1st/  # group shaka
     $DEV_ROOT/projects/misc/<name>/1st/   # group misc
     ```
   - project registry:
     ```text
     ~/.ai/skills-shared/components/projects.yml
     ```
   - active-project registry:
     ```text
     ~/.dots/refs/dev-env/active-projects.md
     ```

4. **Validate base directories:**
   - require `$DEV_ROOT/_tasks/` and the selected group’s code parent to exist
   - selected group parents:
     ```text
     my    -> $DEV_ROOT/projects/my/
     shaka -> $DEV_ROOT/projects/shaka/
     misc  -> $DEV_ROOT/projects/misc/
     ```
   - do not create those parent directories

5. **Create directories safely:**
   - create the task root, code root, and required `1st` workspace when missing
   - if any target exists as a non-directory, stop and report it
   - leave existing directories in place; do not overwrite or delete anything
   - do not create task folders, draft folders, `task.md`, or `steps.md`

6. **Initialize Git:**
   - inspect `<code-root>/1st/` after it exists
   - if it already has a `.git` file or directory, report that Git is already initialized
   - otherwise run:
     ```bash
     git -C <code-root>/1st init
     ```
   - if Git initialization fails, report the error and leave created directories in place

7. **Create and register the project layout:**
   - require `~/.config/tmuxinator/default.yml`
   - create `~/.config/tmuxinator/<project>.yml` by copying that default layout
   - change only its `name` to `<project>`
   - add or verify this registry entry without overwriting an existing entry:
     ```yaml
     <project>:
       checkout_layout: ordinal_workspaces
       code_root: projects/<group>/<name>
       tmux_layout: <project>
       task_provider: local
     ```
   - do not create per-workspace configuration files; all ordinals reuse the project layout

8. **Register the active workspace:**
   - require `~/.dots/refs/dev-env/active-projects.md`
   - verify `<code-root>/1st/` is a Git repo root before registering it
   - compare entries after expanding `$DEV_ROOT`
   - add `$DEV_ROOT/projects/<group>/<name>/1st` under `## Projects` when absent
   - keep project paths sorted and preserve the rest of the file
   - never add inferred sibling workspaces or other projects

9. **Return paths clearly:**
   - show whether the task root, code root, `1st` workspace, Git repo, project registry entry, and active-project entry were created or already existed
   - show the full task root, first workspace, project registry, and active-project registry paths
   - state that Git initializes on `main` or `master`, which is protected for every non-`env` project
   - before `/workit`, tell the user to create and switch to a task branch manually:
     ```bash
     git -C <code-root>/1st switch -c <task-branch>
     ```
   - remind the user:
     ```text
     cd <code-root>/1st && /draftit ...
     /taskit <project> ...
     /workit <project><number> ...
     ```

## Important Notes

- Do not auto-use this skill without the explicit `/projectit` command.
- Create only project-level roots, the `1st` workspace, the project-level tmuxinator layout, and the registry entries.
- Never overwrite, delete, rename, or replace existing files, directories, or registry entries.
- Do not create parent/base directories, per-workspace tmuxinator files, Ghostty shortcuts, or shell aliases.
- This skill creates ordinal-workspace projects. Register existing standalone repositories manually as `checkout_layout: direct` in `projects.yml`.
