---
name: projectit
description: >-
  Create a new project workspace for the task workflow. Creates the task root under
  /Volumes/dev/_tasks/<project>, creates the expected code directory, and runs git init
  there. Command-only skill. Invoke only via /projectit.
---

# Projectit

This is a command-only skill.

## Invocation

Use only:

```text
/projectit help
/projectit <project>
```

Examples:

```text
/projectit help
/projectit my_budget_app
/projectit inventory
```

Do not auto-use this skill from a general project-management request. Wait for the explicit slash command.

## What it does

Create the filesystem roots needed by the task workflow skills:

```text
/Volumes/dev/_tasks/<project>/
```

And create the expected code working directory, then initialize it as a git repository:

```text
/Volumes/dev/mydev/<project>/   # when <project> starts with my_
/Volumes/dev/shaka/<project>/   # otherwise
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
     1. Run /projectit <project> to create /Volumes/dev/_tasks/<project>/.
     2. /projectit also creates the expected code directory:
        - /Volumes/dev/mydev/<project>/ when the project starts with my_
        - /Volumes/dev/shaka/<project>/ otherwise
     3. /projectit runs git init in the code directory.
     4. Then use /draftit, /taskit, and /workit with that project.
     ```
   - otherwise require exactly one token after `/projectit`
   - if the project is missing or extra tokens are present, ask the user to use:
     ```text
     /projectit <project>
     ```

2. **Validate the project name:**
   - `<project>` must be a single safe path segment
   - allow only letters, numbers, underscores, and hyphens
   - do not allow whitespace, `/`, `.` path segments, `..`, or shell metacharacters
   - if invalid, stop and ask for a safe project name such as:
     ```text
     my_budget_app
     inventory
     ```

3. **Resolve paths:**
   - task root:
     ```text
     /Volumes/dev/_tasks/<project>/
     ```
   - code working directory:
     ```text
     /Volumes/dev/mydev/<project>/   # when <project> starts with my_
     /Volumes/dev/shaka/<project>/   # otherwise
     ```

4. **Validate base directories:**
   - require `/Volumes/dev/_tasks/` to exist
   - require `/Volumes/dev/mydev/` to exist when `<project>` starts with `my_`
   - require `/Volumes/dev/shaka/` to exist otherwise
   - if a required base directory is missing, stop and report it
   - do not create `/Volumes/dev`, `/Volumes/dev/_tasks`, `/Volumes/dev/mydev`, or `/Volumes/dev/shaka`

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

7. **Return paths clearly:**
   - show whether the task root was created or already existed
   - show whether the code working directory was created or already existed
   - show whether git was initialized or already present
   - show the full task root path
   - show the full code working directory path
   - remind the user they can now run:
     ```text
     /draftit <project> ...
     /taskit <project> ...
     ```

## Important Notes

- Do not auto-use this skill without the explicit `/projectit` command
- Create only project-level roots; do not create any task-specific files or folders
- Never overwrite, delete, or rename existing files or directories
- Do not create parent/base directories; only create the project task root and project code directory under existing bases
- Running `git init` in an existing non-git code directory is allowed only after confirming `.git` is absent
