---
name: grillme
description: A relentless interview to sharpen a plan or design. When invoked on a file, saves settled results into that file.
disable-model-invocation: true
---

Follow `~/.ai/rules/development-principles.md` throughout this workflow. All
questions, recommendations, and settled decisions must follow those principles.

Read and follow `../grilling/SKILL.md` completely.

Invoke explicitly via `/skill:grillme` (or `/grillme` where that short alias is
exposed) to run a `/grilling` session. An exact bare `grillme` or `1` reply to
Draftit's active standalone continuation offer is equivalent to this explicit
invocation. An exact bare `grillme` reply to Featureit's active continuation
offer uses Featureit's preserved Feature file as the authoritative source.

## Completion and continuation

After grilling completes successfully and the final summary is ready:

1. **Existing non-Feature file:** Grillme has saved the settled results in that
   file. If it matches exactly
   `$DEV_ROOT/_tasks/<project>/draftNN/task.md`, preserve the project and draft
   path and show:

   ```text
   What's next?

   - taskit / 1
   - go-non-stop / 2
   ```

   For any other existing non-Feature file, report the update and stop.
2. **Feature file:** Keep the Feature unchanged and preserve the registered
   project resolved from the Feature path, the validated Feature slug, and the
   final summary. Show:

   ```text
   What's next?

   - draftit / 1
   - go-non-stop / 2
   ```

3. **Conversation or pasted text:** Preserve the final summary and any project
   already resolved from the current workflow. Show:

   ```text
   What's next?

   - draftit / 1
   - go-non-stop / 2
   ```

Handle an offered continuation only when the next reply is one of the exact
bare choices shown by that active menu:

- `taskit` or `1` from an existing-draft menu: read and follow
  `../taskit/SKILL.md` immediately as `/taskit <project> draftNN` using the
  preserved project and draft.
- `draftit` or `1` from a Feature or conversation menu: read and follow
  `../draftit/SKILL.md` immediately using the preserved summary, project when
  available, and Feature only for a Feature-file session.
- `go-non-stop` or `2` from an existing-draft menu: invoke Taskit as above with
  an automatic-handoff authorization.
- `go-non-stop` or `2` from a Feature or conversation menu: invoke Draftit as
  above with an automatic-handoff authorization.

The automatic handoff authorizes only the uninterrupted remaining chain. A
recipient may pass it to the next skill only after completing successfully
without user input. If any recipient fails or needs user input, end the
authorization and use that skill's normal continuation behavior. Do not resume
automatic mode after a pause.

Do not invoke another skill after incomplete or failed Grillme work, before the
user chooses, or for any other reply. Continuation replies do not accept
optional arguments.

## Final principles check

Before reporting the work complete, re-read
`~/.ai/rules/development-principles.md` and double-check all work against every
principle. Explicitly list every part that does not follow a principle and
explain why. If everything follows, say that there are no exceptions.
