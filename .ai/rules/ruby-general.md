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
