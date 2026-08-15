---
name: projectit
description: >-
  Create an ordinal-workspace project for the task workflow. Creates its task
  root, first code workspace, Git repository, tmuxinator layout, registry
  entry, and active-project entry. Offers optional explicitly approved tmux and
  Neovim task-search shortcuts. Command-only skill. In Pi, invoke via
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
/Volumes/dev/_tasks/shaka_p1/
/Volumes/dev/projects/shaka/p1/1st/
```

Group mappings:

```text
my    -> project key my_<name>,    code root /Volumes/dev/projects/my/<name>/
shaka -> project key shaka_<name>, code root /Volumes/dev/projects/shaka/<name>/
misc  -> project key misc_<name>,  code root /Volumes/dev/projects/misc/<name>/
```

It initializes the `1st` workspace as a Git repository, registers an `ordinal_workspaces` project in:

```text
/Users/inseybo/.ai/skills-shared/components/projects.yml
```

and adds the workspace repo root to:

```text
/Users/inseybo/.dots/refs/dev-env/active-projects.md
```

Additional workspaces use positive ordinals such as `2nd`, `7th`, and `28th`.
Tmux sessions use `<project-key><number>`. At the end, the skill suggests
available one-letter tmux and Neovim task-search shortcuts but adds each only
after explicit approval.

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
   - active-project registry:
     ```text
     /Users/inseybo/.dots/refs/dev-env/active-projects.md
     ```
   - tmux project bindings:
     ```text
     /Users/inseybo/.dots/.tmux-projects.conf
     ```
   - Neovim project task bindings:
     ```text
     /Users/inseybo/.dots/.config/nvim/lua/plugins/fzf-lua.lua
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

8. **Register the active workspace:**
   - require `/Users/inseybo/.dots/refs/dev-env/active-projects.md`
   - verify `<code-root>/1st/` is a Git repo root before registering it
   - add the full `<code-root>/1st` path under `## Projects` when absent
   - keep project paths sorted and preserve the rest of the file
   - never add inferred sibling workspaces or other projects

9. **Offer an optional tmux shortcut:**
   - read `/Users/inseybo/.dots/.tmux-projects.conf`
   - inspect lowercase one-letter bindings in the `user-sessions` key table
   - show the available lowercase letters and suggest one meaningful available letter based on `<name>`
   - ask whether the user wants to add a shortcut and which letter to use
   - do not edit the tmux config without explicit approval given after showing the suggestion
   - if approved, require exactly one available lowercase letter; refuse an existing binding rather than replacing it
   - add this project binding alongside the existing project aliases:
     ```text
     bind-key -T user-sessions <letter> set-option -q @tmux-project <project> \; switch-client -T user-project-workspaces
     ```
   - do not reload tmux automatically; tell the user to reload the config after adding a binding

10. **Offer an optional Neovim task-search shortcut:**
   - read `/Users/inseybo/.dots/.config/nvim/lua/plugins/fzf-lua.lua`
   - inspect lowercase one-letter suffixes already used by `<leader>tt<letter>` mappings
   - show the available lowercase letters and suggest one meaningful available letter based on `<name>`
   - tmux and Neovim letters are independent and may use the same letter when it is available in both
   - ask whether the user wants to add a shortcut and which letter to use
   - do not edit the Neovim config without explicit approval given after showing the suggestion
   - if approved, require exactly one available lowercase letter; refuse an existing binding rather than replacing it
   - derive `<project-label>` from `<project>` by converting `_` and `-` to spaces and title-casing the words
   - add this project binding alongside the existing project task bindings:
     ```lua
     map_with_cursor_restore('n', '<leader>tt<letter>', fzf.files, { cwd = '<task-root>', raw_cmd = 'rg --files --sortr modified' }, '[Fzf] Search <project-label> tasks')
     ```
   - tell the user to restart Neovim after adding a binding

11. **Return paths clearly:**
   - show whether the task root, code root, `1st` workspace, Git repo, project registry entry, and active-project entry were created or already existed
   - show the full task root, first workspace, project registry, and active-project registry paths
   - show whether each optional tmux and Neovim shortcut was added or skipped
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
- Create only project-level roots, the `1st` workspace, the project-level tmuxinator layout, the registry entries, and explicitly approved tmux and Neovim task-search bindings.
- Never overwrite, delete, rename, or replace existing files, directories, registry entries, or shortcut bindings.
- Do not create parent/base directories, per-workspace tmuxinator files, Ghostty shortcuts, or shell aliases.
- This skill creates ordinal-workspace projects. Register existing standalone repositories manually as `checkout_layout: direct` in `projects.yml`.
