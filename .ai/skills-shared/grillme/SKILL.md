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
active continuation offer is equivalent to this explicit invocation. An exact
bare `grillme` reply to Featureit's active continuation offer uses Featureit's
preserved Feature file as the authoritative source.

## Completion and continuation

After grilling completes successfully and the final summary is ready:

1. **Existing non-Feature file:** Grillme has saved the settled results in that
   file. If it matches exactly
   `/Volumes/dev/_tasks/<project>/draftNN/task.md`, offer `taskit`, preserve the
   project and draft path, and tell the user to reply with exact bare `taskit`.
   For any other existing non-Feature file, report the update and stop.
2. **Feature file:** Keep the Feature unchanged and offer `draftit` to create one
   Feature-linked draft from the settled capability. Preserve project `env`, the
   validated Feature slug, and the final summary. Tell the user to reply with
   exact bare `draftit`.
3. **Conversation or pasted text:** Offer `draftit` to create one draft from the
   settled result. Preserve the final summary and any project already resolved
   from the current workflow. Tell the user to reply with exact bare `draftit`.

Handle an offered continuation only when the next reply is its exact bare
keyword:

- `taskit`: read and follow `../taskit/SKILL.md` immediately as
  `/taskit <project> draftNN` using the preserved project and draft.
- `draftit`: read and follow `../draftit/SKILL.md` immediately using the
  preserved summary, project when available, and Feature only for a Feature-file
  session.

Do not invoke another skill after incomplete or failed Grillme work, before the
user chooses, or for any other reply. Continuation replies do not accept
optional arguments.

## Final principles check

Before reporting the work complete, re-read
`~/.ai/rules/development-principles.md` and double-check all work against every
principle. Explicitly list every part that does not follow a principle and
explain why. If everything follows, say that there are no exceptions.
