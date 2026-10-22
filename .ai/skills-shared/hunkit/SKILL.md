---
name: hunkit
description: >-
  Show Hunkit usage, or launch Hunk for the current repository's working tree
  or one specified commit in an existing idle tmux pane directly right of Pi,
  optionally use an explicit task file for intent context, then explain the
  focused hunk or walk fixed snapshots in narrative order with explanations,
  optional focused review, and first-parent commit continuation.
  Command-only skill. In Pi,
  invoke via /skill:hunkit; /hunkit
  is also accepted where that alias is exposed.
allowed-tools:
  - "read"
  - "bash(git -C * rev-list *)"
  - "bash(git -C * show -s *)"
  - "bash(git -C * show *:*)"
  - "bash(hunk session get *)"
  - "bash(hunk session context *)"
  - "bash(hunk session review *)"
  - "bash(hunk session navigate *)"
  - "bash(hunk session reload *)"
  - "bash(ruby ~/.ai/skills-shared/hunkit/scripts/hunkit.rb)"
  - "bash(ruby ~/.ai/skills-shared/hunkit/scripts/hunkit.rb *)"
disable-model-invocation: true
---

# Hunkit

Launch one Hunk working-tree or commit review beside the current Pi and keep the existing Pi as the explanation agent. Do not start another Pi process.

## Invocation

```text
/skill:hunkit
/skill:hunkit --diff [--task <path>]
/skill:hunkit <commit> [--task <path>]
/hunkit
/hunkit --diff [--task <path>]
/hunkit <commit> [--task <path>]
```

With no argument, print this brief help and stop without inspecting Git, tmux, or Hunk:

```text
Usage:
  /hunkit --diff [--task <path>]      Review unstaged and untracked changes
  /hunkit <commit> [--task <path>]    Review a specific commit

Then use expit, expall, or revall.
```

Accept exactly `--diff` or one Git commit reference, followed optionally by `--task <path>`. Reject a task without a review source, another argument order, additional arguments, or any other option with the same usage text.

## Optional task context

When `--task <path>` is present:

1. Require the explicit path. Do not infer, search for, or resolve a task from the branch, project, commit, or repository.
2. Resolve a relative path from Pi's current working directory and read the complete file before running the launcher. If it cannot be read, report the error and stop without inspecting Git, tmux, or Hunk.
3. Preserve the resolved path and content for the active Hunkit session. The task remains read-only.
4. Use it as context for intended scope, acceptance criteria, and the reason behind the change. Do not treat the task as proof that the implementation is correct or force the code into a stale plan.
5. Report a `Task mismatch:` separately from a code finding, and only when the complete snapshot and relevant code support a concrete contradiction, missing requirement, or unrelated scope. Do not infer that a requirement is missing from one focused hunk alone.

Without `--task`, keep the existing behavior.

## Start the session

1. After loading any optional task context, run the launcher with only the review source:

   ```text
   ruby ~/.ai/skills-shared/hunkit/scripts/hunkit.rb --diff
   ruby ~/.ai/skills-shared/hunkit/scripts/hunkit.rb <commit>
   ```

   With `--diff`, the launcher validates Hunk-visible working-tree changes and starts `hunk diff --watch`. With a commit, it resolves the reference to an exact commit and starts `hunk show <sha>` without inspecting or changing the working tree. Both modes validate the Git repository and existing left-Pi/right-idle-shell tmux layout before sending any keys. Do not launch Hunk yourself or modify the tmux layout if validation fails.
2. Preserve the repository, target pane, resolved commit when printed, and optional task context as the active Hunkit session.
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
continue
```

Do not treat them as active outside the same Hunkit conversation. `next` is valid only while an `expall` or `revall` walkthrough or skipped-hunk replay is active. During an active walkthrough, treat a clear request to review the skipped hunks as `show skipped`. `continue` is valid only after Hunkit has completed a commit walkthrough and recorded a suggested next commit.

### `expit`

1. Run `hunk session context --repo <repository> --json` to identify Hunk's current focus.
2. If no diff hunk is focused, ask the user to focus one in Hunk and stop.
3. Inspect the review structure with `hunk session review --repo <repository> --json`, then add `--include-patch` only when the focused patch text is needed.
4. Explain the focused hunk in the Pi pane. State:
   - its intent;
   - what behavior changes;
   - why the change matters;
   - how it relates to the optional task goal or acceptance criteria when the connection is direct.
5. Mention a directly evident concrete bug or risk only when supported by the patch and relevant nearby code. Label it `Risk:`. Do not perform a full code review.

Do not navigate Hunk for `expit`; the user controls its current focus.

### Narrative walkthrough order

Build this order once from the complete immutable snapshot before starting either `expall` or `revall`:

1. Start with the smallest set of hunks that makes the change's purpose clearest. When task context exists, use its goal and acceptance criteria to identify those intent anchors. Prefer public behavior, tests or specs that state the intended outcome, configuration, entry points, or representative call sites when they reveal the goal.
2. Continue through the behavior's execution flow from callers and orchestration into the core implementation.
3. Follow with supporting helpers, internal refactors, data plumbing, and low-level details.
4. Leave generated, mechanical, and repetitive updates until last; the default repetition skipping rules may omit them from the main walkthrough.
5. Use the patches and their relationships rather than filenames alone. Preserve Hunk's original relative order when two hunks are equally informative or their relationship is uncertain.
6. Retain each item's original file path and one-based Hunk hunk number for navigation. Hunk's displayed diff is not reordered; `hunk session navigate` moves its focus through the narrative queue.
7. Do not rebuild or reorder the queue after the walkthrough starts.

### `expall`

1. Capture the current ordered Hunk review, including the patch text needed for every hunk. Treat this returned review as an immutable snapshot for the walkthrough. If the complete snapshot cannot be read, do not start a partial walkthrough.
2. Build and retain the narrative queue defined above, containing each captured file, original one-based hunk number, and patch. Initialize empty processed-change signatures and skipped-hunk queues for this snapshot.
3. Navigate Hunk to the first narrative hunk using `hunk session navigate`.
4. Explain it using the same boundaries as `expit`, then retain a concise signature of its material change for snapshot-wide deduplication.
5. Report `Walkthrough 1 of N` with the file and original hunk number, then wait for the exact bare reply `next`.

A new `expall` discards any prior walkthrough, replay, and deduplication state; captures a new snapshot; and records explanation-only mode.

### `revall`

1. Read `.ai/rules/development-principles.md` from the active repository when present; otherwise use `~/.ai/rules/development-principles.md`.
2. Capture and retain the same complete immutable snapshot, narrative queue, and empty deduplication state required by `expall`. Record explanation-plus-review mode.
3. Navigate Hunk to the first narrative hunk.
4. Explain the hunk using the same boundaries as `expit`.
5. Review that hunk against the development principles and relevant nearby code. In working-tree mode, inspect the current file. In commit mode, inspect the appropriate file side from the preserved commit with `git show <commit>:<path>` or its parent rather than trusting the current checkout.
   - report only concrete, actionable findings supported by a complete causal chain;
   - use `Needs investigation` only when a potentially material risk has a credible trigger but required evidence is unavailable;
   - otherwise report `No findings`;
   - report a supported task/code contradiction separately as `Task mismatch:`;
   - do not turn style preferences, speculative edge cases, or one hunk's lack of a task requirement into findings.
6. Retain a concise signature of the hunk's material change for snapshot-wide deduplication.
7. Report `Walkthrough 1 of N` with the file and original hunk number, then wait for the exact bare reply `next`.

A new `revall` discards any prior walkthrough, replay, and deduplication state and captures a new snapshot.

### Default repetition skipping

Apply this behavior to both `expall` and `revall` across the entire retained narrative queue, including across file boundaries:

1. Treat a later hunk as repetitive only when its complete material change is mechanically equivalent to a processed-change signature, such as the same identifier rename or the same call-site replacement, and it adds no distinct behavior.
2. When similarity or additional behavior is uncertain, keep the hunk; do not skip it.
3. Retain every skipped hunk in narrative queue order. Do not remove it from the immutable snapshot or walkthrough queue.
4. Group consecutive or related skipped hunks for reporting. State the repeated transformation, skipped count, and file/hunk locations.
5. A skipped hunk is not considered explained or reviewed. It remains available for replay.

### `next`

1. If skipped-hunk replay is active, navigate to and process the next retained skipped hunk individually using the walkthrough's `expall` or `revall` mode. Do not deduplicate during replay.
2. Otherwise, use only the retained walkthrough queue and its recorded mode. Do not call `hunk session review` or rebuild the snapshot.
3. Scan forward from the current position in the narrative queue. Move repetitive hunks into the retained skipped queue until reaching the first distinct hunk or the end of the queue.
4. Navigate Hunk directly to the next distinct hunk, then explain the retained patch. In `revall` mode, also perform the focused development-principles review defined above. Retain its material-change signature after processing.
5. Report every group skipped during this advance before reporting `Walkthrough N of M` with the file and original hunk number and waiting for `next`.
6. In working-tree mode, if watch mode removed a retained hunk, keep the snapshot unchanged, say that the live display changed, and explain or review the retained hunk without pretending Hunk is focused on it.
7. If no distinct hunks remain, report the final skipped groups and that the main walkthrough is complete. Keep skipped hunks available for replay, then follow the commit-continuation rules below.

### `show skipped`

1. Use only the retained skipped queue. If it is empty, say that no hunks are waiting for replay.
2. Save the current main-walkthrough position and whether it had completed, then enter replay mode.
3. Navigate to the first skipped hunk and process it individually using the active walkthrough's explanation-only or explanation-plus-review mode. Do not deduplicate replayed hunks.
4. Report `Skipped hunk 1 of N` and wait for `next`.
5. During replay, each `next` advances exactly one skipped hunk in retained narrative queue order.
6. After the final skipped hunk, clear the replayed skipped queue. If the main walkthrough was incomplete, navigate back to its saved current hunk and wait for `next`; otherwise report that the walkthrough is complete and repeat any recorded next-commit suggestion.

### Commit continuation

Apply this only after completing an `expall` or `revall` walkthrough launched for a commit. Do not suggest commits for `--diff`.

1. Verify that the preserved full commit SHA appears as an exact line on `HEAD`'s first-parent chain with `git -C <repository> rev-list --first-parent HEAD`. If it does not, say that the next commit is ambiguous and do not guess.
2. Find the immediate newer first-parent commit with `git -C <repository> rev-list --first-parent --reverse <commit>..HEAD` and select only the first returned SHA. Use ancestry order, never author or commit timestamps.
3. If there is no returned SHA, report that the reviewed commit is already the newest commit on the current first-parent chain.
4. Read the selected commit's subject with `git -C <repository> show -s --format=%s <sha>` and retain its exact SHA as the suggested next commit.
5. Suggest continuing with the short SHA and subject. If skipped hunks remain, also report their count and say they can still be replayed with `show skipped`; continuing will discard that prior-commit walkthrough state.
6. Wait for either `continue`, `show skipped`, or another user request. Do not advance automatically.

### `continue`

1. Require a retained suggested next commit and an active Hunk session from the completed commit walkthrough.
2. Reload that same Hunk session with `hunk session reload --repo <repository> -- show <next-commit>`. Do not launch another Hunk process or alter the tmux layout.
3. If reload fails, preserve the current state and report the failure.
4. On success, discard the previous commit's walkthrough, replay, skipped-hunk, and deduplication state; update the active commit to the suggested SHA; and preserve the optional task context.
5. Start a fresh immutable snapshot and narrative queue immediately in the same mode as the completed walkthrough: explanation-only for `expall`, or explanation-plus-review for `revall`.

## Boundaries

- Explanations and reviews appear in Pi only. Add Hunk inline notes only after a separate explicit user request.
- `revall` explicitly authorizes the focused review described above. Outside `revall`, do not perform a full review unless the user separately and explicitly requests one.
- Do not edit code, stage changes, or run checks unless the user separately and explicitly requests that action.
- Never create, split, move, swap, select, replace, reset, close, or kill tmux panes, windows, sessions, shells, or processes.
- Never close Hunk. The user exits it manually in the right pane, returning to the pane's existing shell and working directory.
- Do not reuse an already-running Hunk process through a new Hunkit invocation; the launcher requires an idle right pane.
