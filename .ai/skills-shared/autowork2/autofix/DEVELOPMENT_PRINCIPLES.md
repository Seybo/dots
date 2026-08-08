# Autofix development principles

## Purpose of this file

This file records the Autofix-specific development principles agreed before
building `autofix`, the eventual replacement for `addressit`.

Follow the shared principles in `~/.ai/rules/development-principles.md`. This file
adds only context that cannot be reliably inferred from Autofix code, tests,
comments, or task instructions. Runtime behavior belongs in code. Non-obvious
implementation reasons should be recorded beside the relevant code.

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

## Application shape

- Implement Autofix as a Ruby CLI with a thin Pi skill.
- Use Ruby for application behavior. External executables may provide system
  capabilities, but workflow logic must not be split into shell scripts.
- Keep the fixed three-pane workflow:
  - `agent-manager` settles issues, coordinates Reviews, creates commits, and performs the final review.
  - `agent-worker` performs implementation and the one final Worker review Work Cycle.
  - `agent-reviewer` performs independent Reviewer review Work Cycles.
- Reviewer reviews every implementation Work Cycle until it reports no issues. Worker review runs at most once per Review, after Reviewer first passes. Later implementations caused by Worker-reported issues return through Reviewer and do not trigger another Worker review.
- Do not build a generic agent executor, provider SDK integration, background job
  system, plugin system, or concurrency framework.
- Build a modular monolith: one CLI and one SQLite database, split into small,
  cohesive files by responsibility.
- Autofix must be self-contained. Do not depend on Addressit or Autowork
  internals. Accept small duplication. Consider shared code only after the
  independent Autofix and future Autowork replacements demonstrate the same
  stable need.

## Deterministic behavior and agent judgment

- Ruby owns deterministic mechanics such as validation, state changes,
  persistence, selection, and required input handling.
- Manager invokes `gh`, `tmux`, `pbpaste`, and read-only Git commands needed to
  collect import context, then gives their structured results to Ruby. Ruby does
  not invoke external commands during import.
- After an approved issue authorizes Git mutation, Ruby owns deterministic Git
  staging and Work Cycle commit creation. After the Review is completed, Ruby
  owns an optional local squash only when the operator approves it. Autofix does
  not push.
- One `/skill:autofix` invocation continues through the entire normal Review workflow. A later invocation is only for resuming after an error, interruption, or another stop condition.
- Manager blocks in Ruby while waiting for a Worker or Reviewer Work Cycle
  result and performs no other Autofix work. Interruption preserves that
  incomplete Work Cycle; resume waits for the same result without redispatch.
  An interrupted inline Manager review reuses and performs the same incomplete
  Manager Work Cycle again.
- Agent prompts own judgment such as normalizing feedback, choosing an
  implementation, and reviewing a result.
- Manager uses a critical approach throughout the Review. It actively looks for missing requirements, contradictions, gotchas, incomplete work, and regressions while preserving operator ownership of reported-issue decisions.
- `SKILL.md` owns Manager's external-command and agent orchestration. Delegate
  deterministic workflow behavior to the Ruby CLI instead of duplicating it.
- Manager and Ruby own every Work Cycle lifecycle and all Autofix database
  writes. Every role reports completion through the same structured result
  transport; those files are not authoritative state.

## Autofix language and naming

- Use the domain terms Reported Issue, Review, Work Cycle, Manager, Worker, and
  Reviewer consistently.
- Name root services for their complete use case and lower-level services for
  their exact effect. Use `Handle` for use-case orchestration, `Store` for
  database writes, `Find` for lookup without mutation, `Resolve` for deriving a
  canonical value, and `Render` for text output.
- A singular service name acts on one item. Use a plural name only when the
  service owns collection behavior.
- Name a loaded Reported Issue record `issue` and a collection of those records
  `issues`, never `row` or `rows`. Use `reported_issues` for the Sequel dataset.
- Use `issue_data` for unstored issue hashes and add a source or state qualifier
  only when it distinguishes the value, such as `github_issue_data`,
  `normalized_issue_data`, or `unassigned_issue_data`.
- Use `review_input` for parsed import content and `json_path` for the path to
  its JSON file. Do not use generic names such as `payload` or `path` when the
  narrower meaning is known.
- Use explicit identifier and value suffixes such as `_id`, `_sha`, and `_name`.
- Keep Work Cycle terms distinct: `role` identifies the participant, `action`
  identifies the work, `inputs` are Reported Issues received by the participant,
  and `reported_issues` are Reported Issues produced by review.
- Prefer separate tables for distinct relationships over a generic relationship
  table with a discriminator, as with `work_cycle_inputs` and
  `work_cycle_reported_issues`.

## Ruby conventions

- Use the shared package-root `ServiceObject` mixin, originally copied from
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
autowork2/
  app/services/
  config/boot.rb
  config/database.rb
  db/migrations/
  spec/
  Gemfile
  autofix/
    app/services/
    app/prompts/
    spec/
    bin/autofix
    SKILL.md
```

The exact files should emerge from implementation needs; this is a layout guide,
not a requirement to create empty scaffolding.

## SQLite and Sequel

- SQLite is the authoritative persistent store.
- Use the `sequel` and `sqlite3` gems in the same direct style as `my_health`.
- Keep a small shared `Database` module for the connection and database path.
  Its default runtime path is `db/autowork.db`; use `AUTOWORK_DB_PATH` and
  `AUTOWORK_TEST_DB_PATH` for runtime and test overrides.
- Use direct Sequel datasets from services.
- Use explicit `Sequel.migration` files.
- Use a `MigrateDatabase` ServiceObject around `Sequel::Migrator`.
- Do not create ORM models, callbacks, or a repository layer.
- Put genuine data invariants in SQLite with foreign keys, unique indexes, and
  check constraints. Let violations raise naturally.
- Persist each source import's issue changes, Review, and `review_issues` links
  in one transaction so a failed import leaves no partial Review.
- Every persisted table must declare an integer primary `id` with Sequel's
  `primary_key :id`; SQLite generates its value automatically. Application
  services must not calculate or supply IDs.
- Every persisted table must have a non-null `created_at` timestamp supplied when
  the row is inserted. Add `updated_at` only when a concrete workflow needs it.
  Keep domain identity enforced separately with unique constraints.
- Work Cycles, Reviews, reported issues, decisions, and agent provenance belong
  in SQLite. Generated JSON result files are transport, not authoritative state.
- Manager is Autofix's only database writer. Participants read their authoritative
  context through the deterministic `autofix show-work-cycle <id>` command; do
  not give them arbitrary SQLite command access.
- Do not support legacy Addressit state.

The exact schema, persisted workflow boundaries, state names, and handoff
protocol are intentionally deferred to implementation-task grilling.

## Git ownership

- Invoking Autofix does not authorize Git mutation by itself.
- The first approved issue in a Review authorizes Autofix's deterministic
  Ruby workflow to stage that Review's changes and create local `Work cycle
  <id>` commits. It does not authorize squashing them. After the Review is
  completed, the operator may separately approve one local `Review N` squash
  and pushes separately when ready.
- Require a clean working tree immediately before every Work Cycle so
  participants act on a stable committed state and Manager cannot commit
  unrelated existing changes. Preserve the Review for resume when this
  check fails.
- Worker implementation temporarily creates unstaged changes. Ruby stages and creates one new `Work cycle <id>` commit when implementation completes, returning the tree to clean before the next Work Cycle.
- Review Work Cycles do not modify the checkout. Every implementation Work Cycle creates another new interim commit; Autofix never amends an interim Work Cycle commit.
- Finalization runs checks, validates the exact Work Cycle commit sequence, and completes the Review without changing commit history. Manager then asks `Should i squash?`.
- An approved squash replaces the Review's implementation commits with one local `Review N` commit. Declining, failure, or success does not change the already-completed Review or persist squash state.
- A Review with no approved issues authorizes no Git mutation and does not
  require a clean working tree.
- Push, force-push, branch changes, and unrelated Git operations remain unauthorized.
  Rebase is authorized only by the explicit `/skill:autofix --rebase-base`
  operation.

## Prompts

- Store runtime prompt sources under `app/prompts/`.
- Prompts should be structured Markdown because it is easier for agents and
  humans to read.
- Use `.md` for static prompts and `.md.erb` when runtime interpolation is
  required. Render delivered prompts as Markdown.
- Use Ruby's standard `ERB`; do not add a template framework.
- Keep GitHub issue normalization in
  `app/prompts/normalize_github_issue.md` and shared Work Cycle participant
  instructions in `app/prompts/work_cycle.md`. Global agent rules make the exact message
  `AutoFixCycle <id>` load those instructions; participants read role, action,
  inputs and review-reported issues from SQLite.
- Do not generate or persist dynamic Work Cycle prompts. Use headings, lists,
  and code fences in static prompts when they improve clarity.

## Failures and safety

- Work Cycle participants report inability to complete through a structured
  `failed` result with a sanitized error. Manager exposes the error, leaves the
  Work Cycle incomplete, retains the result file, and does not retry or commit.
- Process successful implementation results in one straight sequence: stage,
  commit, persist completion, advance state, and delete the result.
  Fail immediately without cross-system transaction or recovery machinery.
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

- Use a real temporary SQLite database in specs. Run real migrations and roll
  each example back in a transaction, following the `my_health` test setup.
- Do not mock Sequel.
- Do not test `gh`, `git`, or `tmux` behavior.
- Do not build elaborate command fakes, stubs, or dependency-injection layers
  solely for tests. Prefer simpler and less reliable tests over complex tests
  coupled to implementation details.
- Before every manual QA round, read `qa.md`, show the operator the applicable prerequisites, and wait for confirmation that the environment is ready. Trust that confirmation and do not inspect prerequisite state. Verify actual workflow outcomes after QA starts.
- Test external integration manually.
- Use local RSpec and RuboCop as quality gates.
- Do not add coverage thresholds, static typing, or CI initially.

## Documentation

- Do not create an Autofix README or architecture documentation by default.

## Development process

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
- A run may own one bounded Review.
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
