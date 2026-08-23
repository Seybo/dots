---
name: hunkit
description: >-
  Launch Hunk for the current repository in an existing idle tmux pane directly
  right of Pi, then explain the focused hunk or walk a fixed diff snapshot one
  hunk at a time. Command-only skill. In Pi, invoke via /skill:hunkit; /hunkit
  is also accepted where that alias is exposed.
allowed-tools:
  - "bash(hunk session get *)"
  - "bash(hunk session context *)"
  - "bash(hunk session review *)"
  - "bash(hunk session navigate *)"
  - "bash(ruby ~/.ai/skills-shared/hunkit/scripts/hunkit.rb)"
disable-model-invocation: true
---

# Hunkit

Launch one Hunk working-tree review beside the current Pi and keep the existing Pi as the explanation agent. Do not start another Pi process.

## Invocation

```text
/skill:hunkit
/hunkit
```

Reject arguments with:

```text
Usage: /hunkit
```

## Start the session

1. Run:

   ```text
   ruby ~/.ai/skills-shared/hunkit/scripts/hunkit.rb
   ```

   The launcher validates the Git repository, Hunk-visible working-tree changes, and the existing left-Pi/right-idle-shell tmux layout before sending any keys. Do not launch Hunk yourself or modify the tmux layout if validation fails.
2. Preserve the repository and target pane printed by the launcher as the active Hunkit session.
3. Confirm the live Hunk session with `hunk session get --repo <repository> --json`. If Hunk is still starting, retry once. If no matching session exists after that, report the startup failure without closing or resetting either pane.
4. Report that Hunk is ready and wait. Mention only the available triggers: `expit` and `expall`.

## Active-session triggers

These are exact bare conversational continuations after a successful Hunkit invocation:

```text
expit
expall
next
```

Do not treat them as active outside the same Hunkit conversation. `next` is valid only while an `expall` walkthrough is active.

### `expit`

1. Run `hunk session context --repo <repository> --json` to identify Hunk's current focus.
2. If no diff hunk is focused, ask the user to focus one in Hunk and stop.
3. Inspect the review structure with `hunk session review --repo <repository> --json`, then add `--include-patch` only when the focused patch text is needed.
4. Explain the focused hunk in the Pi pane. State:
   - its intent;
   - what behavior changes;
   - why the change matters.
5. Mention a directly evident concrete bug or risk only when supported by the patch and relevant nearby code. Label it `Risk:`. Do not perform a full code review.

Do not navigate Hunk for `expit`; the user controls its current focus.

### `expall`

1. Capture the current ordered Hunk review, including the patch text needed for every hunk. Treat this returned review as an immutable snapshot for the walkthrough. If the complete snapshot cannot be read, do not start a partial walkthrough.
2. Build and retain an ordered queue containing each captured file, one-based hunk number, and patch. Do not refresh this queue from Hunk while the walkthrough is active.
3. Navigate Hunk to the first captured hunk using `hunk session navigate`.
4. Explain it using the same boundaries as `expit`.
5. Report `Hunk 1 of N` and wait for the exact bare reply `next`.

A new `expall` discards any prior walkthrough queue and captures a new snapshot.

### `next`

1. Use only the retained `expall` queue. Do not call `hunk session review` or rebuild the snapshot.
2. Navigate Hunk to the next captured file and hunk, then explain the retained patch.
3. If watch mode removed that hunk, keep the snapshot unchanged, say that the live display changed, and explain the retained hunk without pretending Hunk is focused on it.
4. Report `Hunk N of M` and wait for `next`, or report that all captured hunks are explained after the final item.

## Boundaries

- Explanations appear in Pi only. Add Hunk inline notes only after a separate explicit user request.
- Do not edit code, stage changes, run checks, or perform a full review unless the user separately and explicitly requests that action.
- Never create, split, move, swap, select, replace, reset, close, or kill tmux panes, windows, sessions, shells, or processes.
- Never close Hunk. The user exits it manually in the right pane, returning to the pane's existing shell and working directory.
- Do not reuse an already-running Hunk process through a new Hunkit invocation; the launcher requires an idle right pane.
