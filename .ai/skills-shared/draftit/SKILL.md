---
name: draftit
description: >-
  Create the next draftNN folder for the current or preserved task project from
  conversation context, deriving a short task slug automatically. An explicit
  feature ID or Grillme handoff may supply optional Feature membership.
  Command-only skill. In Pi, invoke via /skill:draftit; /draftit is also
  accepted where that alias is exposed.
disable-model-invocation: true
---

# Draftit

Follow `~/.ai/rules/development-principles.md` throughout this workflow. The
draft's scope, requirements, and implementation constraints must follow those
principles.

This is a command-only skill.

## Invocation

```text
/skill:draftit
/draftit
/skill:draftit help
/draftit help
/draftit <context-reference-or-text>
/draftit --feature_id <feature-slug> [context-reference-or-text]
```

Examples:

```text
/draftit
/draftit the above plan
/draftit add CSV export for the current report
/draftit --feature_id user-login add password reset
```

A direct invocation with no context argument infers the task context from the
immediately preceding coherent discussion. If that discussion does not contain
enough information for a useful task, ask the user for context instead of
searching further back.

A direct invocation infers the project only from the current registered
checkout. If that state is unavailable, stop and tell the user to invoke
Draftit from the intended project's checkout. Do not accept a project, epic,
name, or slug argument.

A direct invocation may begin with exactly one `--feature_id <feature-slug>`
pair. The value identifies a Feature within the inferred project's Feature
root. Reject a missing value, a duplicate pair, or any other option-style
argument.

An exact bare `draftit` or `1` reply to Grillme's active continuation offer may
use the project and Feature preserved by Grillme. An exact bare `go-non-stop` or
`2` reply may supply the same context with an automatic-handoff authorization.
Explicit `--feature_id` and Grillme Feature state are mutually exclusive. Never
infer an active Feature from older conversation or durable state.

Do not auto-use this skill from a general drafting request. Wait for the explicit
slash command, a shown exact bare continuation reply, or Grillme's authorized
automatic handoff.

## What it does

Create the next available `draftNN` folder under:

```text
$DEV_ROOT/_tasks/<project>/
```

Then write `task.md` from the requested context. When an explicit feature ID or
authorized handoff supplies Feature membership, write the Feature reference
first and append the draft to that Feature's ordered inventory. After standalone
creation, let the user choose whether to grill or convert that draft without
copying another slash command.

## Instructions

1. **Parse and validate the invocation:**
   - if the only argument is `help`, show this help text and stop
   - for a direct invocation, detect and remove one optional leading `--feature_id <feature-slug>` pair before resolving context; reject a missing value, duplicate pair, or any other option-style argument
   - when no context argument remains, infer context from the immediately preceding coherent discussion; if it does not describe a useful task, show the invocation forms and ask for context
   - reject project, epic, name, and slug arguments; Draftit derives the project from the current checkout or an authorized handoff
   - for a direct slash command, resolve the project from the current registered checkout using [`task-resolution.md`](../components/task-resolution.md); stop when it cannot be inferred
   - for a Grillme handoff, use its preserved project when available; use its Feature only when the authoritative source is `$DEV_ROOT/_tasks/<project>/features/<feature-slug>.md`
   - reject an explicit feature ID when Grillme already supplied Feature state
   - do not inspect Pi session logs, prompt templates, other task directories, Git history, older conversation, or persisted state to infer missing routing context

2. **Resolve the project and optional Feature:**
   - read the project from `~/.ai/skills-shared/components/projects.yml`; if it is not registered, stop and tell the user to add it to the registry
   - if its task root does not exist, create `$DEV_ROOT/_tasks/<project>/`
   - without an explicit feature ID or Feature state from Grillme, create an unfeatured draft
   - with either Feature source, validate the slug with `^[a-z][a-z0-9-]*$` and resolve `$DEV_ROOT/_tasks/<project>/features/<feature-slug>.md`
   - the Feature file must exist; read it completely and require its final first-level section to be `# Drafts and tasks` before creating the draft

3. **Resolve context and derive the slug:**
   - with no context argument, use only the immediately preceding coherent discussion that led to the invocation; do not combine unrelated earlier topics
   - for references such as `the above plan`, use the relevant conversation content
   - for literal text, use that text
   - for commits, PRs, review comments, or external threads, inspect the source and rewrite it as self-contained context
   - derive a short, simple slug that names the user-visible task outcome, normally using two to six words
   - lowercase the derived name, replace separators and spaces with `-`, remove characters except letters, numbers, and `-`, collapse repeated `-`, and trim leading/trailing `-`
   - require the result to match `^[a-z][a-z0-9-]*$`; if useful context cannot produce a valid slug, ask for clearer context rather than accepting a name

4. **Write useful task content:**
   - use the derived task slug as the source for the concise task title
   - store the title in `# Story details`; do not render the slug as a heading inside `# Context`
   - lead `# Context` with the user/product problem, not implementation details
   - include expected behavior and acceptance criteria when context supports them
   - do not add implementation planning; `/workit` creates `steps.md` later
   - put source links in `## References`
   - preserve explicitly deferred questions in a final `# Deferred decisions` section using the complete Question / Why this is open / Recommendation format; omit the section when there are no deferred decisions

5. **Use the task structure:**
   - every draft is provider-neutral:
     ```md
     # Story details

     Name: {task slug with `-` replaced by spaces}

     # Context

     {draft content}
     ```
   - Draftit never writes `Epic:`; Taskit collects Shortcut epic state during conversion when needed
   - when an explicit feature ID or authorized handoff supplied Feature membership, prepend the exact Feature reference and one blank line:
     ```md
     Feature: [<feature-slug>](../features/<feature-slug>.md)

     # Story details
     ```
   - do not copy the Feature brief or inventory into `task.md`; the reference loads the shared context

6. **Choose the draft folder:**
   - scan only first-level folders matching exactly `draftNN`, where `NN` is a two-digit positive integer
   - choose the smallest missing number from `01` through `99`
   - stop if all are used

7. **Create the draft:**
   - require `$DEV_ROOT/_tasks/<project>/draftNN/` not to exist
   - create `$DEV_ROOT/_tasks/<project>/draftNN/`
   - create `task.md` only; never modify an existing draft
   - add exactly one trailing newline
   - for a featured draft, append `- [draftNN](../draftNN/task.md)` to the ordered Feature inventory only after `task.md` exists
   - re-read the new `task.md` and Feature file and verify their links agree

8. **Report and continue:**
   - show the draft name, draft folder, and `task.md` path; show the Feature path when present
   - preserve the resolved project, `draftNN`, and full `task.md` path for the next turn
   - inspect the final `# Deferred decisions` section when present; if it contains any question, remind the user that Taskit will pause before conversion so they can either approve preserving the unresolved decisions or answer them directly
   - after successful creation through Grillme's automatic handoff, read and follow `../taskit/SKILL.md` immediately as `/taskit <project> draftNN`, pass the automatic-handoff authorization, and do not display an intermediate menu
   - after successful creation through Grillme's guided continuation, show:

     ```text
     What's next?

     - taskit / 1
     ```

   - after successful standalone creation, show:

     ```text
     What's next?

     - grillme / 1
     - taskit / 2
     ```

   - in the active standalone menu, treat exact bare `grillme` or `1` as an explicit Grillme invocation; read and follow `../grillme/SKILL.md` immediately with the full `task.md` path as its authoritative source
   - treat exact bare `taskit`, `1` from the guided menu, or `2` from the standalone menu as an explicit Taskit invocation; read and follow `../taskit/SKILL.md` immediately as `/taskit <project> draftNN`
   - if automatic draft creation fails or needs user input, end the automatic-handoff authorization and follow normal Draftit behavior; do not resume it after a pause
   - do not invoke another skill for any other reply, after failed or incomplete draft creation, or before the user chooses
   - continuation replies must contain only an exact bare choice from the active menu; optional arguments are not supported

## Important Notes

- Drafts are provider-neutral; Taskit owns Shortcut epic collection and conversion.
- Draftit always derives the slug from context. Rename a draft ad hoc later if its generated name needs correction.
- Do not register projects automatically.
- Do not add extra files.
- Do not auto-use this skill without an explicit `/draftit` command, a shown exact bare continuation reply, or Grillme's authorized automatic handoff.

## Final principles check

Before reporting the work complete, re-read
`~/.ai/rules/development-principles.md` and double-check all work against every
principle. Explicitly list every part that does not follow a principle and
explain why. If everything follows, say that there are no exceptions.
