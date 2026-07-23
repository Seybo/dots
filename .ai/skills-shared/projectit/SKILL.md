---
name: projectit
description: >-
  Create an ordinal-workspace project for the task workflow. Creates its task
  root, first code workspace, Git repository, tmuxinator layout, and registry
  entry. Command-only skill. In Pi, invoke via /skill:projectit; /projectit is
  also accepted where that alias is exposed.
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
/Volumes/dev/_tasks/shaka_p1/
/Volumes/dev/projects/shaka/p1/1st/
```

Group mappings:

```text
my    -> project key my_<name>,    code root /Volumes/dev/projects/my/<name>/
shaka -> project key shaka_<name>, code root /Volumes/dev/projects/shaka/<name>/
misc  -> project key misc_<name>,  code root /Volumes/dev/projects/misc/<name>/
```

It initializes the `1st` workspace as a Git repository and registers an `ordinal_workspaces` project in:

```text
/Users/inseybo/.ai/skills-shared/components/projects.yml
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
   - task root:
     ```text
     /Volumes/dev/_tasks/<project>/
     ```
   - code root and required first workspace:
     ```text
     /Volumes/dev/projects/my/<name>/1st/     # group my
     /Volumes/dev/projects/shaka/<name>/1st/  # group shaka
     /Volumes/dev/projects/misc/<name>/1st/   # group misc
     ```
   - project registry:
     ```text
     /Users/inseybo/.ai/skills-shared/components/projects.yml
     ```

4. **Validate base directories:**
   - require `/Volumes/dev/_tasks/` and the selected group’s code parent to exist
   - selected group parents:
     ```text
     my    -> /Volumes/dev/projects/my/
     shaka -> /Volumes/dev/projects/shaka/
     misc  -> /Volumes/dev/projects/misc/
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
       code_root: <code-root>
       tmux_layout: <project>
       task_provider: local
     ```
   - do not create per-workspace configuration files; all ordinals reuse the project layout

8. **Return paths clearly:**
   - show whether the task root, code root, `1st` workspace, Git repo, and registry entry were created or already existed
   - show the full task root, first workspace, and registry paths
   - state that Git initializes on `main` or `master`, which is protected for every non-`env` project
   - before `/workit`, tell the user to create and switch to a task branch manually:
     ```bash
     git -C <code-root>/1st switch -c <task-branch>
     ```
   - remind the user:
     ```text
     /draftit <project> ...
     /taskit <project> ...
     /workit <project><number> ...
     ```

## Important Notes

- Do not auto-use this skill without the explicit `/projectit` command.
- Create only project-level roots, the `1st` workspace, the project-level tmuxinator layout, and the registry entry.
- Never overwrite, delete, or rename existing files or directories.
- Do not create parent/base directories, per-workspace tmuxinator files, Ghostty shortcuts, or shell aliases.
- This skill creates ordinal-workspace projects. Register existing standalone repositories manually as `checkout_layout: direct` in `projects.yml`.
