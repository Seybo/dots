---
name: grillme
description: A relentless interview to sharpen a plan or design. When invoked on a file, saves settled results into that file.
disable-model-invocation: true
---

Follow `~/.ai/rules/development-principles.md` throughout this workflow. All
questions, recommendations, and settled decisions must follow those principles.

Read and follow `../grilling/SKILL.md` completely.

Invoke explicitly via `/skill:grillme` (or `/grillme` where that short alias is
exposed) to run a `/grilling` session. An exact bare `grillme` reply to Draftit's
active continuation offer is equivalent to this explicit invocation.

## Conversational continuation

After grilling completes successfully and the final summary is ready:

- If the authoritative source is a file matching exactly
  `/Volumes/dev/_tasks/<project>/draftNN/task.md`, offer `taskit` for that draft.
  Preserve the project, `draftNN`, and full `task.md` path.
- Otherwise, offer both:
  - `featureit` to create an `env` Feature from the settled interview result
  - `draftit` to create one draft from the settled interview result
- For a non-draft file-backed session, preserve the updated source file as the
  context reference. For an idea-only session, preserve the settled conversation
  plan. In both cases, keep the recent final summary as the handoff context.
- For Draftit's handoff only, preserve project `env` and the Feature slug when
  the authoritative source is exactly
  `/Volumes/dev/_tasks/env/features/<feature-slug>.md` or starts with the exact
  Feature reference from `task-resolution.md`. Otherwise preserve only a project
  that was already resolved from the authoritative source; never infer Feature
  membership from conversation history.

Tell the user to reply with one offered exact bare keyword; do not require them
to copy or retype a slash command. Handle the next reply as follows:

- `taskit` is an explicit Taskit invocation for the preserved project and draft;
  read and follow `../taskit/SKILL.md` immediately as `/taskit <project> draftNN`.
- An exact bare `featureit` reply is an explicit Featureit invocation with the
  preserved settled interview result; read and follow `../featureit/SKILL.md`
  immediately as bare `/featureit`.
- `draftit` is an explicit Draftit invocation with the preserved context; read and
  follow `../draftit/SKILL.md` immediately, passing only the project and optional
  Feature state preserved by the handoff. When Grillme did not resolve a project,
  Draftit requires the current registered checkout.

Do not invoke another skill for any other reply, after incomplete or failed
Grillme work, or before the user chooses. Continuation replies must contain only
an offered exact bare keyword; optional arguments are not supported.

## Final principles check

Before reporting the work complete, re-read
`~/.ai/rules/development-principles.md` and double-check all work against every
principle. Explicitly list every part that does not follow a principle and
explain why. If everything follows, say that there are no exceptions.
