# Autofix development principles

## Purpose of this file

This file records the top-level development principles agreed before building
`autofix`, the eventual replacement for `addressit`.

It exists for implementation agents. It should contain only context that cannot
be reliably inferred from the code, tests, comments, or task instructions.
Runtime behavior belongs in code. Non-obvious implementation reasons should be
recorded in comments beside the relevant code instead of being added here.

The existing `addressit` skill remains in use while `autofix` is developed.
Autofix starts clean and does not need to read, migrate, or resume Addressit
state.

## Primary context

- Autofix is a personal local-development tool for one user on one known setup.
- It should be maintained and easy to change, but it is not a production-grade
  product.
- It does not need to be perfect or handle every edge case.
- Unexpected conditions may fail loudly. An agent can inspect the exception,
  stack trace, and code when a failure occurs.
- Build for the normal current workflow. Add support for unusual cases only
  after real usage demonstrates the need.

## Operator visibility

- Autofix runs locally for its owner. No Autofix domain or runtime metadata is
  confidential from the operator.
- Show identifiers, database IDs, paths, source values, commands, workflow
  state, and errors when they make the implementation or interaction simpler.
- Do not add hidden state, indirection, or alternate identifiers merely to keep
  implementation details out of operator-facing output.
- Credentials, authentication data, and secrets are not Autofix domain data.
  Keep them out of code, persisted debug data, and committed files because those
  artifacts may leave the local machine.

## Priority of principles

1. KISS is the main design principle.
2. DRY comes after KISS. Small duplication is preferable to a harder abstraction.
3. YAGNI follows from those priorities. Do not build hypothetical flexibility,
   compatibility, recovery, or extension points.
4. Use the simplest current assumption and change the code when reality proves
   it wrong.

## Application shape

- Implement Autofix as a Ruby CLI with a thin Pi skill.
- Use Ruby for application behavior. External executables may provide system
  capabilities, but workflow logic must not be split into shell scripts.
- Keep the fixed three-pane workflow:
  - `agent-manager` coordinates the run through the Ruby CLI.
  - `agent-worker` performs implementation and other worker actions.
  - `agent-reviewer` performs reviewer actions.
- Do not build a generic agent executor, provider SDK integration, background job
  system, plugin system, or concurrency framework.
- Build a modular monolith: one CLI and one SQLite database, split into small,
  cohesive files by responsibility.
- Autofix must be self-contained. Do not depend on Addressit or Autowork
  internals. Accept small duplication. Consider shared code only after the
  independent Autofix and future Autowork replacements demonstrate the same
  stable need.

## Deterministic behavior and agent judgment

- Ruby owns deterministic mechanics such as state changes, persistence, command
  execution, GitHub fetching, Git operations, agent dispatch, and required
  input handling.
- Agent prompts own judgment such as evaluating feedback, choosing an
  implementation, and reviewing a result.
- `SKILL.md` should only contain what Pi needs to invoke and operate the CLI. It
  must not duplicate the workflow implementation.

## Language and naming

- Use simple, concise, accurate language everywhere: code, database names,
  prompts, tests, task files, and documentation.
- Prefer the shortest name that preserves the full meaning. Remove words already
  clear from the local context, but do not shorten names into ambiguity.
- Use established domain terms consistently. Avoid synonyms and unnecessary
  abbreviations.
- A singular service name acts on one item. Use a plural name only when the
  service owns collection behavior.
- Keep headings, sentences, examples, and explanations short. Include details
  that affect behavior; remove repetition and filler.

## Ruby conventions

- Prefer explicit, boring Ruby and one obvious execution path.
- Use a local copy of the `ServiceObject` mixin from
  `/Volumes/dev/projects/my/my_health/1st/app/services/service_object.rb`.
- ServiceObjects expose `.call`, declare keyword arguments with `arguments`, keep
  instance `call` concise, delegate to private methods, and memoize private
  lookups where useful.
- Use ServiceObjects for application actions and meaningful workflow steps.
  Plain classes or modules may handle data, command execution, and small helper
  behavior. Do not turn every method into a ServiceObject.
- The small, familiar metaprogramming inside `ServiceObject` is intentional. Do
  not grow it into a framework.
- Prefer the Ruby standard library when it is simpler. Use mature, focused gems
  when they remove meaningful work. Do not use application frameworks or build
  wrappers speculatively.

## Project layout

Follow the familiar shape used by `my_health`:

```text
autofix/
  app/services/
  app/prompts/
  config/boot.rb
  config/database.rb
  db/migrations/
  spec/
  bin/autofix
  Gemfile
  SKILL.md
```

The exact files should emerge from implementation needs; this is a layout guide,
not a requirement to create empty scaffolding.

## SQLite and Sequel

- SQLite is the authoritative persistent store.
- Use the `sequel` and `sqlite3` gems in the same direct style as `my_health`.
- Keep a small `Database` module for the connection and database path.
- Use direct Sequel datasets from services.
- Use explicit `Sequel.migration` files.
- Use a `MigrateDatabase` ServiceObject around `Sequel::Migrator`.
- Do not create ORM models, callbacks, or a repository layer.
- Put genuine data invariants in SQLite with foreign keys, unique indexes, and
  check constraints. Let violations raise naturally.
- Every persisted table must declare an integer primary `id` with Sequel's
  `primary_key :id`; SQLite generates its value automatically. Application
  services must not calculate or supply IDs.
- Every persisted table must have a non-null `created_at` timestamp supplied when
  the row is inserted. Add `updated_at` only when a concrete workflow needs it.
  Keep domain identity enforced separately with unique constraints.
- Runs, reported issues, decisions, and agent results belong in SQLite. Generated
  Markdown or JSON handoff files are not authoritative state.
- Do not support legacy Addressit state.

The exact schema, persisted workflow boundaries, state names, and handoff
protocol are intentionally deferred to implementation-task grilling.

## Prompts

- Store runtime prompt sources under `app/prompts/`.
- Prompts should be structured Markdown because it is easier for agents and
  humans to read.
- Use `.md` for static prompts and `.md.erb` when runtime interpolation is
  required. Render delivered prompts as Markdown.
- Use Ruby's standard `ERB`; do not add a template framework.
- Give each agent action its own self-contained prompt. Do not build shared
  partial machinery until repeated real use proves it helpful.
- Use headings, lists, and code fences when they improve clarity. Do not force
  every prompt into a generic schema.

## Failures and safety

- Native Ruby and gem exceptions are acceptable, including `NoMethodError`,
  `KeyError`, `JSON::ParserError`, and SQLite constraint errors.
- Do not add validations merely to make every error friendlier.
- Add explicit protection only when it prevents state corruption, protects a
  destructive Git operation, preserves a critical invariant, or adds essential
  external context such as command stderr.
- Avoid shell interpolation of external text. Keep credentials out of code,
  logs, errors, and persisted debug data.
- Trust the local user and machine. Do not build authentication, authorization,
  sandboxing, multi-user behavior, or production hardening.
- Do not add automatic retries, fallback behavior, or speculative recovery.

## Configuration and portability

- Encode the current known environment directly.
- Centralize stable assumptions rather than scattering magic values.
- Expose configuration only for values that genuinely change between runs.
- Do not design for unknown machines, users, repositories, or providers.
- Backward compatibility between Autofix increments is never assumed. During each
  task's grilling session or when planning implementation, explicitly decide
  whether existing inputs and behaviors are retained, replaced, or removed. If
  this was not discussed, stop and ask rather than adding compatibility support.

## Testing and quality

- Test the core happy path, important deterministic behavior, important database
  constraints, and regressions for real bugs.
- Use a real temporary SQLite database in specs. Run real migrations and roll
  each example back in a transaction, following the `my_health` test setup.
- Do not mock Sequel.
- Do not test `gh`, `git`, or `tmux` behavior.
- Do not build elaborate command fakes, stubs, or dependency-injection layers
  solely for tests. Prefer simpler and less reliable tests over complex tests
  coupled to implementation details.
- Test external integration manually.
- Use local RSpec and RuboCop as quality gates.
- Do not add coverage thresholds, static typing, or CI initially.

## Documentation and comments

- Code and tests are authoritative for mechanics.
- Prefer comments beside code over separate documentation.
- Comments explain only non-obvious intent, constraints, or reasons. They must
  not paraphrase visible behavior.
- Do not create a README or architecture documentation by default.
- This file is an exception because multiple implementation tasks need the same
  non-inferable development constraints before the code exists.

## Development process

- Build one end-to-end happy path first.
- Refactor only where working code demonstrates a need.
- Do not design the complete architecture, schema, or reusable components
  upfront.
- Keep the existing Addressit operational while Autofix is developed.
- Create Autofix through separate implementation tasks.
- Start each implementation task with a task-specific grilling session.
- Store that session's decisions in the implementation task and make the task
  reference this file.

## Tentative product direction

The opening part of the grilling session touched product behavior before the
session was narrowed to development principles. These answers are retained so
that they are not lost, but they are not binding and must be reconsidered during
future task-specific grilling:

- Autofix may be outcome-compatible with Addressit rather than interface-compatible.
- Its intended role may be a supervised closer rather than a fully autonomous
  system or a passive assistant.
- A run may own one bounded feedback round.
- Human supervision may use an initial scope gate and a final-result gate.

## Explicitly deferred

The following were not decided in this session:

- Exact Autofix workflow and feature scope.
- Exact SQLite schema and state model.
- Which workflow boundaries must support resume.
- Exact tmux handoff and status protocol.
- Migration/takeover timing from Addressit.
- Whether Autofix independently discovers issues beyond supplied feedback.
- Implementation-task boundaries and order.
