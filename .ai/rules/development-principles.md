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

## Credible complexity and findings

Apply this gate only when proposing production handling or an actionable review finding for an edge case, race, or failure mode. Ordinary implementation work needs no explicit assessment.

Before adding complexity or surfacing a finding, establish the complete causal chain:

1. A real supported action or system event triggers the case.
2. The relevant operations can overlap on a realistic timescale, when overlap matters.
3. A specific ordering, interleaving, or failure creates the harmful condition.
4. Observed behavior, documented guarantees, the actual execution path, an established threat model, or an unavoidable failure mode permits that condition naturally.
5. The case causes a concrete observable failure, data loss, security impact, or invariant violation.
6. Likelihood and impact justify attention in the product's actual threat and failure model.
7. The realistic risk justifies the implementation, maintenance, and correctness cost of handling it.

All seven links are required, but a concise paragraph may combine them; fixed headings are optional. Static reasoning is sufficient when it proves the chain—a production incident is not required. Asynchrony, overlap, timing measurements, or harmful ordering alone do not prove the next link.

Synthetic delays or injected faults may make a regression test deterministic only after a credible production mechanism is established. Instrumentation-only behavior, contrived interaction sequences, and unsupported failure assumptions do not justify production complexity. Rare cases remain valid when they have credible causes or material impact, including process interruption, disk or network failure, hostile input, security-boundary violations, or concurrency the real system permits.

If any required link is missing, investigate it before proposing production handling or an actionable finding. Exploratory review stages may retain unverified concerns internally.

When a potentially material security or data-loss risk has a credible trigger but a required link cannot be verified with available access, present it separately as **Needs investigation**. Name only the missing evidence and how to verify it; do not call it a defect, assign severity, or prescribe production handling.

Prefer the simplest design that preserves required security, data integrity, and domain invariants.

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
