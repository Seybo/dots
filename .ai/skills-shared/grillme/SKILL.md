---
name: grillme
description: A relentless interview to sharpen a plan or design. When invoked on a file, saves settled results into that file.
disable-model-invocation: true
---

Read and follow `../grilling/SKILL.md` completely.

Invoke explicitly via `/skill:grillme` (or `/grillme` where that short alias is
exposed) to run a `/grilling` session. An exact bare `grillme` reply to Draftit's
active continuation offer is equivalent to this explicit invocation.

## Conversational continuation

After grilling completes successfully and the final summary is ready:

- If the authoritative source is a file matching exactly
  `/Volumes/dev/_tasks/<project>/draftNN/task.md`, offer `taskit` for that draft.
  Preserve the project, `draftNN`, and full `task.md` path.
- Otherwise, offer `draftit` using the settled interview result as context. For a
  file-backed session, preserve the updated source file as the context reference;
  for an idea-only session, preserve the settled conversation plan.

Tell the user to reply with the offered bare keyword; do not require them to copy
or retype a slash command. If the next user message is exactly that keyword:

- `taskit` is an explicit Taskit invocation for the preserved project and draft;
  read and follow `../taskit/SKILL.md` immediately as `/taskit <project> draftNN`.
- `draftit` is an explicit Draftit invocation with the preserved context; read and
  follow `../draftit/SKILL.md` immediately, letting Draftit resolve the project by
  its normal rules when Grillme did not resolve one.

Do not invoke another skill for any other reply, after incomplete or failed
Grillme work, or before the user chooses. Continuation replies must contain only
the exact bare keyword; optional arguments are not supported.
