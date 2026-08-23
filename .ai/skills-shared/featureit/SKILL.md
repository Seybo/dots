---
name: featureit
description: >-
  Research a user-provided env Feature idea, create its durable Feature file,
  then hand that Feature to Grillme for incremental development into drafts.
  Command-only skill. In Pi, invoke via /skill:featureit; /featureit is also
  accepted where that alias is exposed.
disable-model-invocation: true
---

# Featureit

Follow `~/.ai/rules/development-principles.md` throughout this workflow.

This is a command-only skill for the registered `env` project.

## Invocation

```text
/skill:featureit <feature-idea>
/featureit <feature-idea>
```

Example:

```text
/featureit create a tmux extension that copies semantic parts of pane output
```

Require a non-empty natural-language Feature idea. Reject option-style
arguments and project, path, name, slug, or mode options. Featureit derives the
Feature identity and always uses project `env`.

Do not auto-use this skill from a general feature request. Invoke it only through
the slash command.

## What it does

Investigate the Feature idea, then create one Feature file containing the durable
research and shared context for incremental development. Featureit does not grill
the research, propose a split, or create drafts. After creation, it offers
Grillme to settle one capability; Draftit can then create one Feature-linked
draft.

Read and follow [`task-resolution.md`](../components/task-resolution.md) for the
Feature path, reference, inventory, membership, and precedence contract.

## Research the Feature

1. **Resolve the idea:**
   - use the complete invocation text as the Feature idea
   - identify the user-visible outcome and the immediate questions that research
     can answer
   - do not ask the user for information discoverable from local files,
     documentation, or public sources
   - ask one focused question only when the outcome is too unclear to guide
     relevant research or derive a useful Feature identity

2. **Investigate relevant evidence:**
   - inspect relevant local code, configuration, documentation, and established
     project conventions first
   - inspect official documentation or upstream source when technology behavior,
     extension APIs, or supported capabilities matter
   - use the available web-search workflow when current public information or
     comparable projects could materially inform the Feature; do not rely on
     model memory for current ecosystem claims
   - search for existing tools or plugins with similar functionality when they
     could reveal proven capabilities, interaction patterns, or limitations
   - keep research proportional to the Feature; do not perform an exhaustive
     survey or investigate speculative concerns
   - do not install, execute, or trust third-party code as part of research

3. **Produce a self-contained research summary:**
   - state the Feature goal and relevant existing local behavior
   - summarize material findings, constraints, capability options, and the
     simplest recommended starting point
   - preserve recommendations as recommendations rather than settled
     requirements
   - preserve unresolved product decisions as open questions for Grillme
   - include useful source links and local file paths
   - include this concise audit, explicitly marking every category that was not
     performed and why:

     ```md
     ## Research performed

     - Local code and docs: <paths and topics, or "Not performed — <reason>">
     - Official documentation: <sources and topics, or "Not performed — <reason>">
     - Web search: <search topics or queries, or "Not performed — <reason>">
     - Comparable projects: <names and links, or "None found">
     ```

## Create the Feature

1. **Derive the Feature slug:**
   - derive a concise name from the user-visible Feature outcome, normally two to
     six words
   - lowercase it, replace separators and spaces with `-`, remove characters
     except letters, numbers, and `-`, collapse repeated `-`, and trim leading or
     trailing `-`
   - require the derived Feature slug to match `^[a-z][a-z0-9-]*$`; ask for a
     clearer Feature idea if no useful slug can be derived
   - do not accept a manual name or slug override

2. **Resolve the target:**
   - use the fixed Feature root `$DEV_ROOT/_tasks/env/features/`
   - create that directory when missing
   - resolve the target as
     `$DEV_ROOT/_tasks/env/features/<feature-slug>.md`
   - the target Feature file must not already exist; stop rather than overwrite,
     merge, rename, or choose another slug

3. **Write the Feature:**
   - preserve the complete self-contained research summary
   - use this structure and keep `# Drafts and tasks` as the final first-level
     section:

     ```md
     # Feature: <concise feature name>

     # Context

     <complete research summary, including Research performed>

     # Drafts and tasks
     ```

   - do not create draft folders
   - add exactly one trailing newline

4. **Verify and report:**
   - re-read the Feature file
   - verify it preserves the complete research summary and ends with
     `# Drafts and tasks`
   - show the Feature slug and full file path
   - show a concise `Research performed` list using the same four categories from
     the Feature file, including explicit `Not performed` entries
   - preserve the path and slug for the continuation below
   - tell the user to reply with exact bare `grillme` to develop one capability
     from the Feature

## Grillme continuation

An exact bare `grillme` reply to Featureit's active continuation is an explicit
Grillme invocation with the new Feature file as its authoritative source. Read
and follow `../grillme/SKILL.md` immediately using the preserved full Feature
path. Any other reply ends the continuation.

## Boundaries

- Featureit creates Features only for `env`.
- Feature files are local files; do not create drafts, Tasks, Shortcut stories,
  branches, commits, databases, persisted workflow state, or session artifacts.
- Featureit is create-only. Do not reopen, resume, split, overwrite, or add work
  to an existing Feature.
- Feature development proceeds incrementally through repeated
  `Grillme -> Draftit` cycles, one draft at a time.
- Do not invoke Draftit, Taskit, Workit, or another continuation automatically.

## Final principles check

Before reporting the work complete, re-read
`~/.ai/rules/development-principles.md` and double-check all work against every
principle. Explicitly list every part that does not follow a principle and
explain why. If everything follows, say that there are no exceptions.
