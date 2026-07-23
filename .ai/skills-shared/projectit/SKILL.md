---
name: projectit
description: >-
  Create a new project workspace for the task workflow. Creates the task root under
  /Volumes/dev/_tasks/<project>, creates the expected code directory, runs git init
  there, and registers the project workspace/layout mapping. Command-only skill. In Pi, invoke
  via /skill:projectit; /projectit is also accepted where that alias is exposed.
disable-model-invocation: true
---

# Projectit

This is a command-only skill.

## Invocation

In Pi, use either:

```text
/skill:projectit help
/projectit help
/projectit <project>
```

Examples:

```text
/projectit help
/projectit my_budget_app
/projectit shaka_inventory
/projectit misc_notes
```

Do not auto-use this skill from a general project-management request. Wait for the explicit slash command.

## What it does

Create the filesystem roots needed by the task workflow skills:

```text
/Volumes/dev/_tasks/<project>/
```

And create the registered code root's required `1st` workspace, then initialize it as a git repository:

```text
/Volumes/dev/projects/mydev/<project>/1st/   # when <project> starts with my_
/Volumes/dev/projects/shaka/<project>/1st/   # when <project> starts with shaka_
/Volumes/dev/projects/misc/<project>/1st/    # when <project> starts with misc_
```

Register the project workspace/layout mapping in:

```text
/Users/inseybo/.ai/skills-shared/components/projects.yml
```

Additional workspaces use any positive ordinal (`2nd`, `7th`, `28th`, ...). Tmux sessions
use `<project><number>` and are started through the project's tmuxinator layout with the
workspace root injected dynamically.

After this, the project can be used with:

```text
/draftit <project> ...
/taskit <project> ...
/workit <project> ...
```

## Instructions

1. **Parse command arguments:**
   - if the only argument is `help`, show this help text and stop:
     ```text
     Project setup flow:
     1. Run /projectit <project> with a project name starting with my_, shaka_, or misc_.
     2. /projectit creates /Volumes/dev/_tasks/<project>/.
     3. /projectit also creates the expected first workspace:
        - /Volumes/dev/projects/mydev/<project>/1st/ when the project starts with my_
        - /Volumes/dev/projects/shaka/<project>/1st/ when the project starts with shaka_
        - /Volumes/dev/projects/misc/<project>/1st/ when the project starts with misc_
     4. /projectit runs git init in the `1st` workspace.
     5. /projectit registers the project in `~/.ai/skills-shared/components/projects.yml`.
     6. Start a workspace with `mux <project>1`; the project-level tmuxinator layout is reused for later ordinals.
     7. Then use /draftit, /taskit, and /workit with that project.
     ```
   - otherwise require exactly one token after `/projectit`
   - if the project is missing or extra tokens are present, ask the user to use:
     ```text
     /projectit <project>
     ```

2. **Validate the project name:**
   - `<project>` must be a single safe path segment
   - allow only letters, numbers, underscores, and hyphens
   - require one of these prefixes: `my_`, `shaka_`, or `misc_`
   - do not create `env` with `/projectit`; it is the dotfiles infrastructure project
   - do not allow whitespace, `/`, `.` path segments, `..`, or shell metacharacters
   - if invalid, stop and ask for a safe prefixed project name such as:
     ```text
     my_budget_app
     shaka_inventory
     misc_notes
     ```

3. **Resolve paths:**
   - task root:
     ```text
     /Volumes/dev/_tasks/<project>/
     ```
   - code root and required first workspace:
     ```text
     /Volumes/dev/projects/mydev/<project>/1st/   # when <project> starts with my_
     /Volumes/dev/projects/shaka/<project>/1st/   # when <project> starts with shaka_
     /Volumes/dev/projects/misc/<project>/1st/    # when <project> starts with misc_
     ```
   - project registry:
     ```text
     /Users/inseybo/.ai/skills-shared/components/projects.yml
     ```

4. **Validate base directories:**
   - require `/Volumes/dev/_tasks/` to exist
   - require `/Volumes/dev/projects/mydev/` to exist when `<project>` starts with `my_`
   - require `/Volumes/dev/projects/shaka/` to exist when `<project>` starts with `shaka_`
   - require `/Volumes/dev/projects/misc/` to exist when `<project>` starts with `misc_`
   - if a required base directory is missing, stop and report it
   - do not create `/Volumes/dev`, `/Volumes/dev/_tasks`, `/Volumes/dev/projects/mydev`, `/Volumes/dev/projects/shaka`, or `/Volumes/dev/projects/misc`

5. **Create directories safely:**
   - create the task root if it does not exist
   - create the code root and required `1st` workspace if they do not exist
   - if either path exists as a file or non-directory, stop and report it
   - if either directory already exists, leave it in place and report that it already existed
   - do not overwrite or delete anything
   - do not create task folders, draft folders, `task.md`, or `steps.md`

6. **Initialize git:**
   - inspect `<code-root>/1st/` after it exists
   - if it already contains a `.git` directory or file, report that git was already initialized and do not run `git init`
   - otherwise run:
     ```bash
     git -C <code-root>/1st init
     ```
   - if `git init` fails, report the error and leave the created directories in place

7. **Create and register the project layout:**
   - require the default layout at `~/.config/tmuxinator/default.yml`
   - create one project-level layout at `~/.config/tmuxinator/<project>.yml` by copying the default layout
   - change only the layout's `name` to `<project>`; keep its workspace-root and task-root ERB settings
   - add or verify one entry in `~/.ai/skills-shared/components/projects.yml`:
     ```yaml
     <project>:
       code_root: <code-root>
       tmux_layout: <project>
       task_provider: local
     ```
   - preserve an existing project entry instead of overwriting its layout or task provider
   - do not create per-workspace configuration files; all ordinals reuse the project layout

8. **Return paths clearly:**
   - show whether the task root was created or already existed
   - show whether the code root and `1st` workspace were created or already existed
   - show whether git was initialized or already present
   - show whether the registry entry was created or already existed
   - show the full task root path
   - show the full `1st` workspace path
   - show the project registry path
   - remind the user they can now start tmux workspaces and run:
     ```text
     /draftit <project> ...
     /taskit <project> ...
     /workit <project><number> ...
     ```

## Important Notes

- Do not auto-use this skill without the explicit `/projectit` command
- Create only project-level roots, the required `1st` workspace, the project-level tmuxinator layout, and the registry entry; do not create task-specific files or folders
- Never overwrite, delete, or rename existing files or directories
- Do not create parent/base directories; only create the project task root and project code root under existing bases
- Do not create per-workspace tmuxinator files, Ghostty shortcuts, or shell aliases
- Running `git init` in an existing non-git `1st` workspace is allowed only after confirming `.git` is absent
