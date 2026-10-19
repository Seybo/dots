# Ruby/Rails Development Rules

Team conventions for any Ruby/Rails project unless the project's own instructions override them. These are the non-obvious house choices only — use standard Rails/RSpec judgment for everything not listed here.

## Naming

- Boolean attributes, arguments, and variables start with `is_`.
- Count variables end with a count-like suffix that matches the context (`_count`, `_size`, or the project's existing convention).

## Specs

- For code changes, relevant specs and configured RuboCop checks must pass before work is considered done. Do not require them for documentation-only changes or projects that do not provide them. Report checks that fail or cannot run.
- No `send` to call private methods. Assert observable behavior through existing public interfaces. Do not make methods public solely for tests; expose behavior only when the application needs it.
- No `allow_any_instance_of`. Stub on the actual instance you control.
- No `let!` — use `before` blocks for setup with side effects.
- Use `instance_double(ClassName)` with the actual class constant, not a string.
- Prefer factories (FactoryBot or similar) over fixtures when the project supports them.

## Security

- No raw SQL interpolation. Use parameterized queries (`?` placeholders, named params, or ORM query methods).
- API keys, tokens, and other credentials live in environment variables — never in code or committed config.
