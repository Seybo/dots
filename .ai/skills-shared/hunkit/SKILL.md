---
name: hunkit
description: >-
  Show Hunkit usage, or launch Hunk for the current repository's working tree
  or one specified commit in an existing idle tmux pane directly right of Pi,
  then explain the focused hunk or walk a fixed snapshot with explanations and
  optional focused review.
  Command-only skill. In Pi,
  invoke via /skill:hunkit; /hunkit
  is also accepted where that alias is exposed.
allowed-tools:
  - "read"
  - "bash(git -C * show *:*)"
  - "bash(hunk session get *)"
  - "bash(hunk session context *)"
  - "bash(hunk session review *)"
  - "bash(hunk session navigate *)"
  - "bash(ruby ~/.ai/skills-shared/hunkit/scripts/hunkit.rb)"
  - "bash(ruby ~/.ai/skills-shared/hunkit/scripts/hunkit.rb *)"
disable-model-invocation: true
---

# Hunkit

Launch one Hunk working-tree or commit review beside the current Pi and keep the existing Pi as the explanation agent. Do not start another Pi process.

## Invocation

```text
/skill:hunkit
/skill:hunkit --diff
/skill:hunkit <commit>
/hunkit
/hunkit --diff
/hunkit <commit>
```

With no argument, print this brief help and stop without inspecting Git, tmux, or Hunk:

```text
Usage:
  /hunkit --diff      Review unstaged and untracked changes
  /hunkit <commit>    Review a specific commit

Then use expit, expall, or revall.
```

Accept exactly `--diff` or one Git commit reference for a launch. Reject additional arguments or any other option with the same usage text.

## Start the session

1. Run:

   ```text
   ruby ~/.ai/skills-shared/hunkit/scripts/hunkit.rb --diff
   ruby ~/.ai/skills-shared/hunkit/scripts/hunkit.rb <commit>
   ```

   With `--diff`, the launcher validates Hunk-visible working-tree changes and starts `hunk diff --watch`. With a commit, it resolves the reference to an exact commit and starts `hunk show <sha>` without inspecting or changing the working tree. Both modes validate the Git repository and existing left-Pi/right-idle-shell tmux layout before sending any keys. Do not launch Hunk yourself or modify the tmux layout if validation fails.
2. Preserve the repository, target pane, and resolved commit when printed by the launcher as the active Hunkit session.
3. Confirm the live Hunk session with `hunk session get --repo <repository> --json`. If Hunk is still starting, retry once. If no matching session exists after that, report the startup failure without closing or resetting either pane.
4. Report that Hunk is ready and wait. Mention only the available triggers: `expit`, `expall`, and `revall`.

## Active-session triggers

These are exact bare conversational continuations after a successful Hunkit invocation:

```text
expit
expall
revall
next
show skipped
```

Do not treat them as active outside the same Hunkit conversation. `next` is valid only while an `expall` or `revall` walkthrough or skipped-hunk replay is active. During an active walkthrough, treat a clear request to review the skipped hunks as `show skipped`.

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
2. Build and retain an ordered queue containing each captured file, one-based hunk number, and patch. Do not refresh this queue from Hunk while the walkthrough is active. Initialize empty processed-change signatures and skipped-hunk queues for this snapshot.
3. Navigate Hunk to the first captured hunk using `hunk session navigate`.
4. Explain it using the same boundaries as `expit`, then retain a concise signature of its material change for snapshot-wide deduplication.
5. Report `Hunk 1 of N` and wait for the exact bare reply `next`.

A new `expall` discards any prior walkthrough, replay, and deduplication state; captures a new snapshot; and records explanation-only mode.

### `revall`

1. Read `.ai/rules/development-principles.md` from the active repository when present; otherwise use `~/.ai/rules/development-principles.md`.
2. Capture and retain the same complete immutable snapshot and empty deduplication state required by `expall`. Record explanation-plus-review mode.
3. Navigate Hunk to the first captured hunk.
4. Explain the hunk using the same boundaries as `expit`.
5. Review that hunk against the development principles and relevant nearby code. In working-tree mode, inspect the current file. In commit mode, inspect the appropriate file side from the preserved commit with `git show <commit>:<path>` or its parent rather than trusting the current checkout.
   - report only concrete, actionable findings supported by a complete causal chain;
   - use `Needs investigation` only when a potentially material risk has a credible trigger but required evidence is unavailable;
   - otherwise report `No findings`;
   - do not turn style preferences or speculative edge cases into findings.
6. Retain a concise signature of the hunk's material change for snapshot-wide deduplication.
7. Report `Hunk 1 of N` and wait for the exact bare reply `next`.

A new `revall` discards any prior walkthrough, replay, and deduplication state and captures a new snapshot.

### Default repetition skipping

Apply this behavior to both `expall` and `revall` across the entire retained snapshot, including across file boundaries:

1. Treat a later hunk as repetitive only when its complete material change is mechanically equivalent to a processed-change signature, such as the same identifier rename or the same call-site replacement, and it adds no distinct behavior.
2. When similarity or additional behavior is uncertain, keep the hunk; do not skip it.
3. Retain every skipped hunk in original snapshot order. Do not remove it from the immutable walkthrough queue.
4. Group consecutive or related skipped hunks for reporting. State the repeated transformation, skipped count, and file/hunk locations.
5. A skipped hunk is not considered explained or reviewed. It remains available for replay.

### `next`

1. If skipped-hunk replay is active, navigate to and process the next retained skipped hunk individually using the walkthrough's `expall` or `revall` mode. Do not deduplicate during replay.
2. Otherwise, use only the retained walkthrough queue and its recorded mode. Do not call `hunk session review` or rebuild the snapshot.
3. Scan forward from the current main-walkthrough position. Move repetitive hunks into the retained skipped queue until reaching the first distinct hunk or the end of the snapshot.
4. Navigate Hunk directly to the next distinct hunk, then explain the retained patch. In `revall` mode, also perform the focused development-principles review defined above. Retain its material-change signature after processing.
5. Report every group skipped during this advance before reporting `Hunk N of M` and waiting for `next`.
6. In working-tree mode, if watch mode removed a retained hunk, keep the snapshot unchanged, say that the live display changed, and explain or review the retained hunk without pretending Hunk is focused on it.
7. If no distinct hunks remain, report the final skipped groups and that the main walkthrough is complete. Keep skipped hunks available for replay.

### `show skipped`

1. Use only the retained skipped queue. If it is empty, say that no hunks are waiting for replay.
2. Save the current main-walkthrough position and whether it had completed, then enter replay mode.
3. Navigate to the first skipped hunk and process it individually using the active walkthrough's explanation-only or explanation-plus-review mode. Do not deduplicate replayed hunks.
4. Report `Skipped hunk 1 of N` and wait for `next`.
5. During replay, each `next` advances exactly one skipped hunk in original snapshot order.
6. After the final skipped hunk, clear the replayed skipped queue. If the main walkthrough was incomplete, navigate back to its saved current hunk and wait for `next`; otherwise report that the walkthrough is complete.

## Boundaries

- Explanations and reviews appear in Pi only. Add Hunk inline notes only after a separate explicit user request.
- `revall` explicitly authorizes the focused review described above. Outside `revall`, do not perform a full review unless the user separately and explicitly requests one.
- Do not edit code, stage changes, or run checks unless the user separately and explicitly requests that action.
- Never create, split, move, swap, select, replace, reset, close, or kill tmux panes, windows, sessions, shells, or processes.
- Never close Hunk. The user exits it manually in the right pane, returning to the pane's existing shell and working directory.
- Do not reuse an already-running Hunk process through a new Hunkit invocation; the launcher requires an idle right pane.
