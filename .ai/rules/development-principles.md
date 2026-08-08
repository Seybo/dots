# Development principles

Use these defaults unless project-specific instructions require otherwise.

## Priorities

1. KISS is the primary design principle: choose the simplest correct solution.
2. DRY comes after KISS. Small duplication is better than a premature abstraction.
3. Follow YAGNI. Do not build hypothetical flexibility, compatibility, configuration, recovery, or extension points.
4. Change assumptions when real requirements or usage prove them wrong.

## Implementation

- Build the smallest end-to-end working path first.
- Prefer explicit, boring code with one obvious execution path.
- Reuse established project patterns and terminology.
- Refactor only when working code demonstrates a concrete need.
- Introduce abstractions only after repeated behavior reveals a stable boundary.
- Add edge-case handling when there is a credible execution path or observed need.
- Choose the simplest solution that preserves required security, data integrity, and domain invariants.

## Naming

- Use simple, concise, accurate names.
- Prefer established domain terms over synonyms or new naming patterns.
- Name components for their actual responsibility and values for their precise meaning.
- Remove words already clear from local context, but do not abbreviate into ambiguity.

## Testing and documentation

- Test core behavior, important invariants, and regressions for real bugs.
- Prefer behavior-focused tests over tests coupled to implementation details.
- Do not create elaborate test infrastructure solely to support speculative design.
- Treat code and tests as authoritative for mechanics.
- Comments explain non-obvious intent, constraints, or reasons; they do not restate visible behavior.
- Create separate documentation only for context that cannot be reliably inferred from code, tests, or nearby comments.
