# Phases 3.5–4 — saving the report and posting pending comments

Read this file after the Phase 3 markdown is produced.

## Phase 3.5 - Save the report to a file (ALWAYS, automatic)

After printing the Phase 3 markdown, ALWAYS persist the SAME markdown verbatim to a `super-review.md` file. This is not optional and needs no user prompt - the file is the durable artifact; the chat output scrolls away. Write it BEFORE Phase 4 (posting), so the report survives even if the user skips posting.

**Where to write it** (first match wins):

1. **Task folder** - resolve it deterministically, do NOT eyeball or improvise. Resolution follows the shared task-resolution logic (`~/.ai/skills-shared/components/task-resolution.md`):
   - **Project**: if the user passed a `task.md` path or task-folder path, use that folder directly. Otherwise infer the project from the review's working dir using `~/.ai/skills-shared/components/projects.yml`. This supports both ordinal workspaces (for example `$DEV_ROOT/projects/shaka/gtm/2nd/` → `shaka_gtm`) and registered direct checkouts (for example `$DEV_ROOT/oss/rails/` → `rails`); task root is `$DEV_ROOT/_tasks/<project>/`.
   - **Task ID**: from a branch `sc-<digits>` segment when available (e.g. `mikhail/sc-33672/...` → `33672`). For an arbitrary local branch, do not guess a task ID; the user must pass the task folder/path directly. Task folders are named `<id>-<slug>` with NO `sc-` prefix.
   - **Find the folder** with `find`, never a shell glob (a bare zsh glob aborts the whole command on a non-matching pattern and prints `no matches found`, which looks like a real negative but is a broken command):
     ```bash
     find "$DEV_ROOT/_tasks/<project>" -maxdepth 1 -type d -name '<id>-*'
     ```
   - If `find` prints exactly one path, that is the task folder → write `<task-folder>/super-review.md`. If it prints nothing, the task folder genuinely does not exist → fall through to case 2/3. If it prints more than one, ask the user which. **A `find` that errored (non-zero exit) is not an empty result — re-run it before concluding "no task folder"; never route to the fallback on an unverified negative.**
2. **PR review, no task folder** - write to `<repo-root>/super-review.md` in the user's main working dir (NOT the throwaway worktree - it gets removed in Phase 5). If that would clobber an existing unrelated file, use `super-review-pr<num>.md`.
3. **Branch / staged / last-commit review, no task folder** - write to `<repo-root>/super-review.md`.

If a `super-review.md` already exists at the target from a previous run on the SAME scope, overwrite it (the latest review wins). If it exists but covers a DIFFERENT scope, suffix the new one (`super-review-<branch-or-pr>.md`) rather than clobbering.

Use the Write tool, not a shell heredoc. After writing, print one line: `Report saved: <absolute path>`.

The on-disk file is the EXACT Phase 3 output (same headline, ranked findings, Clean section, Stats) - do not summarize or trim it for the file. The interactive shortening rules in Phase 4 apply ONLY to posted PR comments, never to this file.

## Phase 4 - Interactive posting (pending review, NEVER submit)

Do NOT change the review output (Phase 3) - Sasha likes the full ranked format. The interactivity is only at the posting stage.

1. After the review output, ask which findings to leave pending comments on (by their number in the report):
   `Which findings should I leave as pending PR comments? (e.g. "1, 4" / "all High" / "none for now")`
2. For EACH selected finding, leave an inline **pending** comment anchored to the exact line. Not selected - don't comment.
3. NEVER submit without an explicit "submit/send". Pending is the default: Sasha clicks Submit/Discard in GitHub himself.

**STOP before posting:** run the `PRE-POST GATE` below on EVERY drafted comment. Do NOT assemble `payload.json` until all 4 gate items pass. This is not optional - this is exactly where comments bloat.

**Pending mechanic** (NOT `gh pr review --comment` - that submits immediately): create the review via REST WITHOUT the `event` field:
```bash
HEAD=$(gh pr view <num> --repo <owner>/<repo> --json headRefOid -q .headRefOid)
jq -n --arg body "$(cat /tmp/cmt.md)" --arg c "$HEAD" \
  '{commit_id:$c, comments:[{path:"<file>", line:<N>, side:"RIGHT", body:$body}]}' > /tmp/payload.json
gh api -X POST /repos/<owner>/<repo>/pulls/<num>/reviews --input /tmp/payload.json --jq '{id,state,html_url}'
# state == PENDING is required. Multiple findings -> multiple objects in comments[] in ONE POST (one pending review, don't multiply).
```
- A single line is more reliable: send only `line` + `side:"RIGHT"`. `start_line`+`line` via this endpoint often loses the range (the anchor collapses onto the end line).
- You can only anchor to lines inside the diff hunk. Write the comment body to a file (`jq --arg`) - less escaping pain.
- **Body-level / top-level comment** (not anchored to a line: about the PR description, a general point): GitHub's Submit-review dialog opens the summary box EMPTY and does NOT load the API-set `body` → the summary is DROPPED on submit (confirmed on PR#39). So for ANY non-inline comment, ALWAYS hand Sasha the ready-to-paste text and explicitly say "add this as a top-level comment by hand". Never rely on the review `body` reaching the PR via the UI.

## Comment format (LOCKED - "Variant A", Sasha's senior style. Standard approved on PR#40)

**TOP PRINCIPLE: as short as possible.** Write the minimum a senior needs to grasp it and act without opening the file. Cut every word that isn't load-bearing. Length is dictated ONLY by the finding's genuine complexity, never by a target number. There is NO fixed limit (the ~56 words on PR#40 was an observation, NOT a bar): don't pad to look thorough, and don't mechanically trim to hit some number. A simple finding is two lines; a complex mechanism that can't be explained shorter is exactly as long as each clause genuinely needs.

Default structure = **THREE short blocks, separated by a BLANK LINE.** Goal: the comment scans at a glance instead of reading like a wall of text.

1. **Bold takeaway in one sentence: WHAT breaks** (impact, not mechanism).
2. One line, `problem -> consequence`, with `file:line` and identifiers in backticks. One link, not a list.
3. A short, direct ask/question.

Hard rules (a violation means rewrite):
- **Blank lines between blocks are MANDATORY, each block = 1 line.** A dense 3-5 sentence paragraph with no breaks is WRONG, even if correct on substance. If you catch yourself writing a wall of text, split into 3 blocks and drop the filler. (This is the new rule: the skill used to say cram into 1-2 lines as one paragraph - that produced an unreadable block, so we do NOT do that anymore.)
- **Simple English, like a Senior Tech Engineer.** Short words, active voice. NOT academic vocab: "comes back empty" not "resolves to missing"; "stored as if verified" not "stored as first-class"; "response shape" not "envelope"; "won't be retried" not "suppressed from re-selection"; "stuck" not "wedged".
- NO severity tags (`[HIGH]`, `[category]`) and NO `What/Why/Fix` headers.
- **Length is dictated by complexity, not a target number (see TOP PRINCIPLE). Default to the shortest version that's still clear.** The block structure never changes:
  - simple finding → 2 blocks (bold takeaway + question), middle can be dropped.
  - normal → 3 blocks as above.
  - genuinely complex mechanism → add ONLY the detail you can't omit (an extra fact in the middle block, an important caveat in the question's parenthetical) - that is the only thing that justifies length. Every clause earns its place; the block stays 1-2 lines, not a paragraph.
  - do NOT trim a needed explanation to hit a number, and do NOT pad to look thorough - both are wrong.
- For a concrete fix, put a GitHub suggestion block as a separate block AFTER the question. English (GitHub-visible). Don't add AI attribution.

Examples = **THE FORMAT STANDARD. Copy the STRUCTURE (3 blocks, blank lines, plain words), not the text.** All three approved by Sasha on PR#40:

Normal finding (3 blocks):
> **A People Search rerun overwrites the enriched `full_name` with the old search value.**
>
> `last_name` is protected by `preserved_last_name`, `full_name` is not -> after Enrich sets `"Eric Example"`, a rerun drops it back to `"Eric"` while `last_name` stays `"Example"`.
>
> Add a `preserved_full_name` the same way?

With a suggestion block (the fix goes AFTER the question, as its own block):
> **Passing `api:` skips the approval gate, so a live run can spend credits with no `--approve-live-call`.**
>
> The gate checks `api.nil?` instead of `live`. The CLI is safe (never passes `api:`), but a direct `Run.call(api: ...)` reserves and calls `bulk_match` ungated.
>
> Gate on `live` and pass `approve_first_live_call: true` in the specs?
>
> ` ``suggestion ` (GitHub suggestion block with the ready replacement line)

Complex mechanism (middle block a bit denser, but the structure and blank lines hold):
> **If the live response does not echo our `id`, the whole batch comes back as `missing` after a paid call.**
>
> Apollo prospects only match by `id` here, no fallback by design. A wrong response shape means `credits_consumed > 0` but every row gets `email_status: 'missing'` and an `enrichment_date` - so no error, and no retry for 30 days.
>
> Raise when `credits_consumed > 0` but `matched == 0`, so a shape mismatch fails loud?

## PRE-POST GATE (run before EVERY `gh api POST`, binary: failing ANY item = rewrite BEFORE posting)

This fixes the recurring "comments bloat" drift - Sasha caught it 3 times in a row because the advisory "shorter" rule above does NOT fire. This is a hard checklist, not advice. Run every drafted comment through the 4 items:

1. **Middle block = EXACTLY one sentence** (one `problem -> consequence` link). Two sentences = cut to one. Keep a second fact ONLY when the finding can't be understood without it (the "complex mechanism" class), and then it lives in a parenthetical, not a separate sentence.
2. **EXACTLY one question/ask in the final block.** Constructions like "X, or Y?", "confirm X and decide Y", "..., not Z?" are a double ask: collapse to one.
3. **Zero meta-explanations of "how it reads".** Delete perception phrases: "reads as cleanup", "so it looks like", "feels like", "comes across as", "looks like". A comment says WHAT breaks and what it threatens, not how the reader sees it. This is my main source of extra weight - cut it first.
4. **Literal size-diff against the standard.** Put your comment mentally next to the matching PR#40 example (normal / suggestion / complex mechanism). Visibly longer than the standard for its class = cut to its size. The standard is the CEILING for the finding's class, not the floor.

Only after all 4 pass on ALL comments - assemble `payload.json` and post. If you catch yourself thinking "but this needs context" - that's almost always item 3 (explaining framing). Context goes in the Phase 3 ranked output, not the inline comment.
