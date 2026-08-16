---
name: featureit
description: >-
  Create an env Feature file from a completed Grillme summary, propose an ordered
  split, and create the approved drafts through Draftit. Command-only skill. In
  Pi, invoke via /skill:featureit; /featureit is also accepted where that alias
  is exposed.
disable-model-invocation: true
---

# Featureit

Follow `~/.ai/rules/development-principles.md` throughout this workflow.

This is a command-only skill for the registered `env` project.

## Invocation

```text
/skill:featureit
/featureit
```

An exact bare `featureit` reply to Grillme's active continuation offer is
equivalent to this explicit invocation with Grillme's preserved settled result.
Reject arguments; Featureit derives its name and accepts no project, path, name,
or slug option.

Do not auto-use this skill from a general feature request. Invoke it only through
the slash command or Grillme's exact continuation.

## What it does

Create one Feature file from the recent final Grillme summary in the current
conversation, then let the user approve an ordered split into `env` drafts. The
initial file contains the complete settled Feature design. After every approved
draft is created, the file becomes the stable shared brief and ordered draft
inventory.

Read and follow [`task-resolution.md`](../components/task-resolution.md) for the
Feature path, reference, inventory, membership, and precedence contract. Read
and follow [`draftit/SKILL.md`](../draftit/SKILL.md) before creating drafts.

## Create the Feature

1. **Resolve context:**
   - require a successfully completed Grillme session in the current conversation
   - use its recent final settled Grillme summary as the complete source
   - prefer that summary over older discussion that it superseded
   - do not inspect Pi session logs, session JSONL, prompt templates, task folders,
     Git history, or unrelated files to reconstruct context
   - if no completed settled summary is available, stop and tell the user to run
     Grillme first

2. **Derive the Feature slug:**
   - derive a concise name from the user-visible Feature outcome, normally two to
     six words
   - lowercase it, replace separators and spaces with `-`, remove characters
     except letters, numbers, and `-`, collapse repeated `-`, and trim leading or
     trailing `-`
   - require the derived Feature slug to match `^[a-z][a-z0-9-]*$`; ask for clearer
     Feature context if no useful slug can be derived
   - do not accept a manual name or slug override

3. **Resolve the target:**
   - use the fixed Feature root `/Volumes/dev/_tasks/env/features/`
   - create that directory when missing
   - resolve the target as
     `/Volumes/dev/_tasks/env/features/<feature-slug>.md`
   - the target Feature file must not already exist; stop rather than overwrite,
     merge, rename, or choose another slug

4. **Write the initial file:**
   - preserve the complete settled design as useful self-contained Markdown
   - use this structure and keep `# Drafts and tasks` as the final first-level
     section:

     ```md
     # Feature: <concise feature name>

     # Context

     <complete settled Feature design>

     # Drafts and tasks
     ```

   - do not create draft folders yet
   - add exactly one trailing newline

5. **Report and offer the split:**
   - show the Feature slug and full file path
   - preserve the path, slug, and complete initial contents for this continuation
   - ask exactly:

     ```text
     Propose split to drafts?
     ```

## Propose the draft split

An exact `yes` reply presents an ordered draft proposal without creating or
modifying files. Any other reply before a proposal ends this continuation.

Build the proposal from the complete Feature file using these existing planning
rules:

- Build the smallest end-to-end working path first.
- Split by logical behavior, not by files or technical layers. Keep one
  behavior's implementation, callers, configuration, tests, and documentation
  together.
- Order drafts by dependency and cause-and-effect. Every draft leaves the
  environment runnable and adds one useful outcome.
- Split again when one draft crosses more than one substantial integration boundary.
- Do not target a fixed draft count or add speculative work. If a later draft
  changes earlier behavior, state what it retains, replaces, or removes.

For each proposed draft, show its concise title, outcome, task-specific context,
grounded acceptance criteria, and dependencies. Keep shared goals and
constraints assigned to the Feature rather than duplicating them in every
draft. Ensure every task-specific requirement is assigned to at least one draft.

The proposal is read-only conversation state. The user may request revisions;
revise and present the complete ordered proposal again without touching files.
After every proposal or revision, tell the user that exact bare `approve` creates
that displayed version. Do not treat another reply as approval.

## Create the approved drafts

An exact `approve` reply for the currently displayed proposal applies Draftit in
Featureit batch mode:

1. Re-read the complete Feature file and require its path and slug still match
   the preserved continuation.
2. Read and follow `../draftit/SKILL.md` once, then apply its normal content,
   slug, numbering, write, and Feature-inventory rules to every approved draft
   in displayed order with project `env` and the preserved Feature slug.
3. Create one complete `draftNN/task.md` before starting the next draft. Append
   its relative link to the ordered Feature inventory only after that draft file
   exists.
4. Suppress Draftit's normal per-draft Grillme/Taskit continuation while this
   batch is active.
5. If any draft fails, stop. Keep the Feature's complete design and every
   already-created draft/link visible; do not retry, roll back, trim, or invent
   recovery state.
6. Only after every approved draft is created successfully, verify every removed
   task-specific requirement is represented in the created drafts, then trim the
   Feature file to its stable goal, scope, shared constraints, and unchanged
   ordered inventory.
7. Re-read the Feature file and every created `task.md`, verify the references and
   inventory links agree, and report all created draft paths plus the Feature
   path.

## Boundaries

- Featureit creates Features only for `env`.
- Feature files and drafts are local files; do not create Shortcut stories,
  branches, commits, databases, persisted workflow state, or session artifacts.
- Featureit is create-only. Do not reopen, resume, re-split, or overwrite an
  existing Feature.
- Do not invoke Taskit, Workit, or another continuation after the batch. The user
  chooses the normal next workflow explicitly.

## Final principles check

Before reporting the work complete, re-read
`~/.ai/rules/development-principles.md` and double-check all work against every
principle. Explicitly list every part that does not follow a principle and
explain why. If everything follows, say that there are no exceptions.
