<!-- Generated for Pi from shared rule files. Do not edit by hand; regenerate from .ai/rules/ruby-general.md, .ai/rules/agent-ops.md, .ai/rules/abbreviations.md, .ai/rules/placeholder-stubs.md. -->

<!-- Source: .ai/rules/ruby-general.md -->

# Ruby/Rails Development Rules

Universal Ruby and Rails conventions. These apply to any Ruby/Rails project unless that project's `CLAUDE.md` explicitly overrides them. Stack-specific guidance (Sidekiq, GraphQL, particular UI frameworks, project mixins) lives in per-project rule files such as [popmenu.md](popmenu.md).

## Language and naming

- Use simple words and precise technical language.
- Boolean attributes, arguments, and variables should start with `is_`.
- Count variables should end with a count-like suffix that matches the context, such as `_count`, `_size`, or another existing project convention.

## Services

- When the project has a service-object mixin (e.g. `ServiceObject`), include it consistently across service classes.
- Keep `call` concise — delegate to private methods.
- Memoize lookups as private instance methods.

## Specs

- Always make sure specs pass.
- Always make sure RuboCop passes.
- No `send` to call private methods. Test through the public interface; if something needs assertion, expose it.
- No `allow_any_instance_of`. Stub on the actual instance you control.
- No `let!` — use `before` blocks for setup with side effects.
- Use `instance_double(ClassName)` with the actual class constant, not strings.
- Prefer factories (FactoryBot or similar) over fixtures when the project supports them.

## Performance

- Watch for N+1 queries. Use eager loading (`includes`/`preload` in ActiveRecord, `.eager(...)` in Sequel, equivalent in your ORM).
- When you check `.empty?` and then iterate the same collection, materialize once with `.to_a` to avoid re-querying.

## Security

- No raw SQL interpolation. Use parameterized queries (`?` placeholders, named params, or ORM query methods).
- API keys, tokens, and other credentials live in environment variables — never in code or committed config.
- Sensitive data (PII, credentials, raw provider responses with secrets) must not appear in logs, error messages, or stored debug artifacts. Sanitize before logging or persisting.

## GitHub PR reviews

- When the user links a specific GitHub PR review URL or review ID, fetch the review directly with `gh api repos/<owner>/<repo>/pulls/<pr>/reviews/<review_id> --jq '{user: .user.login, state: .state, body: .body}'` and fetch inline comments with `gh api repos/<owner>/<repo>/pulls/<pr>/reviews/<review_id>/comments --jq '.[] | {path: .path, line: .line, body: .body}'`. Do not rely on web fetch or only `gh pr view`; those can miss inline review comments.

<!-- Source: .ai/rules/agent-ops.md -->

# Agent operating rules

General agent workflow and command-use rules. These are language- and project-neutral unless a project's local instructions override them.

## Pi slash commands and skills

When the user asks about a Pi "skill" or `/command`, treat that as any Pi slash command, not only an Agent Skill from `<available_skills>`. Pi slash commands can come from prompt templates (`/name`), Agent Skills (`/skill:name`), extension commands, or built-in commands. If a command appears in Pi autocomplete, it exists even when it is not listed in `<available_skills>`. Do not say a `/command` is unavailable solely because it is absent from `<available_skills>`; ask the user to run it or check prompt templates/commands if needed.

## Git safety

- Never mutate git history, branches, tags, stashes, remotes, or commit state without explicit user approval for that exact action. This includes `commit`, `commit --amend`, `reset`, `rebase`, `merge`, `cherry-pick`, `revert`, `switch`/`checkout` that changes branches, branch create/delete/rename, tag create/delete, stash create/apply/pop/drop, force-push, and remote changes.
- Reading git state is allowed: `status`, `diff`, `log`, `show`, `branch --show-current`, and similar read-only commands.
- Staging files (`git add`) is also a git state mutation. Ask first unless the user explicitly asked to commit or prepare a commit.
- If approval is ambiguous, stop and ask. Do not infer approval from words like "go", "fix it", or "next".

## Command efficiency

- Prefer targeted, low-latency commands over broad scans or mass replacements. Scope `rg`, tests, RuboCop, and file edits to the smallest relevant paths first; run full checks only at step boundaries or when needed.
- Avoid broad `perl -pi`, `sed -i`, or repo-wide replacements when strings overlap (for example rename/revert work). Use precise `edit` replacements or a small script with explicit file lists and post-change verification.
- Before running a command that may take more than a few seconds, state what it will do and why. After it returns, immediately summarize the result and next action.
- To avoid avoidable Pi permission prompts, do not send multiline bash payloads when the same work can be done with separate tool calls or one safe line joined with `;` / `&&`. Pi permission checks handle pipelines/segments better than newline-separated pasted blocks.
- For numbered file snippets, prefer the read tool or `nl -ba <file> | sed -n '<range>p'`; avoid ad-hoc `awk` line-numbering commands when `nl -ba` does the same job.

<!-- Source: .ai/rules/abbreviations.md -->

# Agent abbreviations

These abbreviations are shorthand instructions. They may appear alone or after quoted text.
When the meaning is clear, act on them without asking for clarification.

## Abbreviations

- `00ex` — Explain the referenced text using simple, precise technical terms.
  Prefer a clear paraphrase, then any necessary context.

- `00gf` — Give feedback on the referenced idea or text.
  Do not make changes. Say whether you agree, disagree, or partially agree, and explain why in simple technical terms.

- `00rar` — Read the new/other agent's latest review file in the task folder.
  Locate the current task folder if needed. In Pi, prefer `claude_review*.md`; in Claude, prefer `pi_review*.md`. Use the newest matching review file unless the user names one, and summarize actionable findings before changing code.

- `00rvu` — Review unstaged changes only.
  Do not run specs or RuboCop. Only review the logic, looking for bugs, unhandled edge cases, and similar correctness issues.

<!-- Source: .ai/rules/placeholder-stubs.md -->

# Temporary stubs and placeholders

Temporary stubs are fine and even **encouraged** when building something across multiple
implementation steps. Landing a working skeleton first and filling in real behavior in a later
step — rather than building everything at once — keeps each step small, reviewable, and shippable.

The one hard rule: every temporary stub, placeholder, fake value, hardcoded shortcut, or
"fill this in later" MUST carry this exact marker, on its own comment line directly above the
placeholder code:

```text
!!!! SHOULD BE HANDLED/REMOVED BEFORE MERGE !!!!
```

This applies to anything that must not survive into a merged change: not-yet-implemented method
bodies, stubbed/fake return values, hardcoded data standing in for real input, skipped
validation, a `raise 'NOT_IMPLEMENTED'`, a correctness-blocking TODO, and similar.

## Why

Incremental stubs keep steps small, but a placeholder that slips silently into a merge becomes a
latent bug or a correctness/security gap. The loud, uniform marker makes every such spot
greppable and impossible to miss in review.

## How to apply

- Put the marker on its own comment line immediately above the placeholder, in the file's comment
  syntax (`#`, `//`, `<!-- -->`, etc.).
- Follow it with a short line stating what the real implementation should be and which step adds it.
- Before declaring work merge-ready, grep for the marker (`rg 'SHOULD BE HANDLED/REMOVED BEFORE MERGE'`)
  and confirm none remain — or that any remaining ones are explicitly agreed to defer.
- The marker is permission to stub *between steps*, not permission to merge a stub. Remove or
  implement it before the change is considered done.
