---
name: projectit
description: >-
  Create a new project workspace for the task workflow. Creates the task root under
  /Volumes/dev/_tasks/<project>, creates the expected code directory, runs git init
  there, and creates a matching Zellij layout. Command-only skill. In Pi, invoke
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

And create the expected code working directory, then initialize it as a git repository:

```text
/Volumes/dev/projects/mydev/<project>/   # when <project> starts with my_
/Volumes/dev/projects/shaka/<project>/   # when <project> starts with shaka_
/Volumes/dev/projects/misc/<project>/    # when <project> starts with misc_
```

Also create a matching Zellij layout:

```text
/Users/inseybo/.dots/.config/zellij/layouts/<project>.kdl
```

The layout name and session name are both `<project>`, so the project can be opened with:

```bash
zj <project>
```

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
     3. /projectit also creates the expected code directory:
        - /Volumes/dev/projects/mydev/<project>/ when the project starts with my_
        - /Volumes/dev/projects/shaka/<project>/ when the project starts with shaka_
        - /Volumes/dev/projects/misc/<project>/ when the project starts with misc_
     4. /projectit runs git init in the code directory.
     5. /projectit creates /Users/inseybo/.dots/.config/zellij/layouts/<project>.kdl.
     6. Open or attach the project Zellij session with zj <project>.
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
   - reserve `shaka_gtm` for the existing GTM multi-checkout project; do not create it with `/projectit`
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
   - code working directory:
     ```text
     /Volumes/dev/projects/mydev/<project>/   # when <project> starts with my_
     /Volumes/dev/projects/shaka/<project>/   # when <project> starts with shaka_
     /Volumes/dev/projects/misc/<project>/    # when <project> starts with misc_
     ```
   - Zellij layout:
     ```text
     /Users/inseybo/.dots/.config/zellij/layouts/<project>.kdl
     ```

4. **Validate base directories:**
   - require `/Volumes/dev/_tasks/` to exist
   - require `/Volumes/dev/projects/mydev/` to exist when `<project>` starts with `my_`
   - require `/Volumes/dev/projects/shaka/` to exist when `<project>` starts with `shaka_`
   - require `/Volumes/dev/projects/misc/` to exist when `<project>` starts with `misc_`
   - require `/Users/inseybo/.dots/.config/zellij/layouts/` to exist
   - if a required base directory is missing, stop and report it
   - do not create `/Volumes/dev`, `/Volumes/dev/_tasks`, `/Volumes/dev/projects/mydev`, `/Volumes/dev/projects/shaka`, `/Volumes/dev/projects/misc`, or `/Users/inseybo/.dots/.config/zellij/layouts`

5. **Create directories safely:**
   - create the task root if it does not exist
   - create the code working directory if it does not exist
   - if either path exists as a file or non-directory, stop and report it
   - if either directory already exists, leave it in place and report that it already existed
   - do not overwrite or delete anything
   - do not create task folders, draft folders, `task.md`, or `steps.md`

6. **Initialize git:**
   - inspect the code working directory after it exists
   - if it already contains a `.git` directory or file, report that git was already initialized and do not run `git init`
   - otherwise run:
     ```bash
     git -C <code-working-directory> init
     ```
   - if `git init` fails, report the error and leave the created directories in place

7. **Create the Zellij layout:**
   - layout path:
     ```text
     /Users/inseybo/.dots/.config/zellij/layouts/<project>.kdl
     ```
   - if the layout path exists as a file, leave it unchanged and report that it already existed
   - if the layout path exists as a directory or other non-file, stop and report it
   - otherwise create the layout file with this exact structure, substituting the resolved paths:
     ```kdl
     layout {
         cwd "<code-working-directory>"

         default_tab_template {
             pane size=1 borderless=true {
                 plugin location="zellij:compact-bar"
             }
             children
         }

         tab name="git" {
             pane command="zsh" {
                 args "-lic" "lg"
             }
         }

         tab name="vim" {
             pane command="zsh" {
                 args "-lic" "v"
             }
         }

         tab name="pi" {
             pane command="zsh" {
                 args "-lic" "pi-w"
             }
         }

         tab name="misc" split_direction="horizontal" {
             pane size="80%" cwd="<task-root>" command="zsh" {
                 args "-lic" "lg"
             }
             pane name="misc"
         }
     }
     ```
   - if content does not end with a newline, add exactly one trailing newline

8. **Return paths clearly:**
   - show whether the task root was created or already existed
   - show whether the code working directory was created or already existed
   - show whether git was initialized or already present
   - show whether the Zellij layout was created or already existed
   - show the full task root path
   - show the full code working directory path
   - show the full Zellij layout path
   - remind the user they can now run:
     ```text
     zj <project>
     /draftit <project> ...
     /taskit <project> ...
     ```

## Important Notes

- Do not auto-use this skill without the explicit `/projectit` command
- Create only project-level roots and the matching Zellij layout; do not create any task-specific files or folders
- Never overwrite, delete, or rename existing files or directories
- Do not create parent/base directories; only create the project task root and project code directory under existing bases
- Do not update Zellij keybindings or create per-project shell aliases; `zj <project>` is the scalable open/attach command
- Running `git init` in an existing non-git code directory is allowed only after confirming `.git` is absent
