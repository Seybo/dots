---
name: agent-permissions
description: Update or explain Claude Code and Pi permissions/allowlists. Use when the user asks about permission prompts, allowlisting commands, where permission files live, or how Pi permissions work.
---

# Agent Permissions

Use this skill when changing or explaining agent permissions for Claude Code and/or Pi.

## Canonical reference

Read this first:

```text
~/.dots/refs/dev-env/agent-permissions.md
```

It records the current permission models, source locations, update workflow, and gotchas.

## Default rule

Unless the user explicitly says **Pi only** or **Claude only**, consider both systems. They no longer share the same configuration model:

- Claude Code uses permission rules in `~/.claude/settings.json` and repository `.claude/settings*.json` files.
- Pi uses the owned `repo-permissions` extension at `~/.dots/.pi/agent/extensions/repo-permissions/`.

Do not create or restore `permission.settings.json` files for Pi.

## Pi choices

Choose the smallest option that matches the request:

1. **One operation:** use **Allow once** when Pi prompts.
2. **Temporary unrestricted work:** select **Unrestricted** from `/permissions` or the prompt. It lasts only for the current session.
3. **Trusted skill command:** add the narrow command shape to that local skill's `allowed-tools` frontmatter.
4. **Reusable read-only Bash family:** add it to the extension's built-in policy only when it is broadly safe, useful across repositories, and has behavior-focused specs.
5. **Mutating, executing, or repository-specific Bash:** keep the prompt. Prefer a path-aware `read`, `edit`, or `write` operation when one is equivalent.

Repository mode is not a general allowlist. It automatically handles path-aware operations inside the current Git root and only a small set of validated read-only Bash commands. Mutations to Git metadata such as `.git/config`, worktree `.git` files, and hooks still require approval.

## Procedure

1. Read the canonical reference.
2. Determine whether the request concerns Claude Code, Pi, or both.
3. Inspect the prompted operation and identify why it was not approved automatically.
4. If the command is unsafe or intentionally restricted, do not make it automatic. Explain why and suggest a safer command or path-aware tool when possible.
5. For Claude Code, follow its existing global versus repository-local settings convention. Preserve deny/ask rules and avoid broad executor allows.
6. For Pi, use the smallest applicable choice from **Pi choices** above:
   - do not add project-specific persistent permission configuration
   - do not add broad mutating Bash validation
   - do not let a skill rule bypass direct protected-file checks unless the trusted wrapper itself is the intentional boundary
7. When changing a skill's `allowed-tools`, keep the rule scoped to the exact trusted wrapper or command family the skill owns. Pi's standard space-delimited scalar and the existing YAML list form are both supported.
8. When changing Pi's built-in read-only policy:
   - update `.pi/agent/extensions/repo-permissions/`
   - add or update the relevant `*.test.ts` file
   - run the complete extension specs
   - verify Pi loads the extension without diagnostics
9. QA the safer or newly supported operation shape.
10. Update the canonical reference when behavior or a durable gotcha changes.

## Claude Code reminders

- Prefer global rules only for broadly reusable, low-risk read-only commands.
- Prefer repository-local rules for checkout-specific paths and workflows.
- Avoid broad executor rules such as arbitrary Python, shell wrappers, `pytest`, or `xargs`.
- Run `/doctor` after adding or removing `Bash(...)` rules.

## Pi reminders

- Repository mode starts automatically only when Pi can resolve the Git root and snapshot existing ignored/excluded files.
- Ask mode is the safe fallback outside Git or after repository discovery failure.
- Unrestricted mode explicitly allows everything for the current session.
- Trusted top-level local skills may contribute `allowed-tools`; third-party package skills do not.
- Unknown or mutating Bash commands prompt instead of being guessed safe.
- Recursive commands that follow symlinks, shell brace expansion, mutating Git flags, and Git targets escaping through chained `-C` options prompt.
- In non-interactive modes, operations requiring approval are blocked.
