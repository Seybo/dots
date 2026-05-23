# Ruby/Rails Development Rules

Universal Ruby and Rails conventions. These apply to any Ruby/Rails project unless that project's `CLAUDE.md` explicitly overrides them. Stack-specific guidance (Sidekiq, GraphQL, particular UI frameworks, project mixins) lives in per-project rule files such as [popmenu.md](popmenu.md).

## Services

- When the project has a service-object mixin (e.g. `ServiceObject`), include it consistently across service classes.
- Keep `call` concise — delegate to private methods.
- Memoize lookups as private instance methods.

## Specs

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
