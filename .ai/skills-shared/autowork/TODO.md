# autowork TODO

## Implemented in V1

- three-pane discovery by exact title: `pi-manager`, `pi-worker`, `claude-worker`
- abstract `/autowork doctor` readiness reporting on clean or dirty repos, independent of any task
- default doctor tmux send-keys QA, with `--no-send-test` for read-only checks
- initialization/resume config and state files
- `/workit ... create-steps-only` preflight for missing/updated `steps.md` and branch setup/verification
- send Pi implementation prompt and wait for status JSON
- stage/commit Pi Step N changes
- send Claude review prompt and wait for status JSON
- ask Pi to classify machine-readable Claude findings
- commit accepted fixes as `Step N fix M`
- send accepted-fix commits back to Claude for review
- facilitate bounded Pi/Claude debate for disputed/deferred findings, pausing for operator arbitration if unresolved after the limit
- advance to the next planned step when no actionable findings remain
- run configured final checks, defaulting to RuboCop/RSpec when a Gemfile exists
- commit automated final-check fixes as `Final checks fix M`
- send final-check fix commits to Claude for review
- write `final_checks.md`, `super-review.md`, super-fix artifacts, `manager_review.md`, and `final_summary.md`
- final whole-branch super-review gate after final checks pass:
  - send `/claude-super-review` to `claude-worker` once, scoped to `review_base_ref...HEAD`
  - accept optional full base branch/ref through `/autowork <task_id> <full-base-branch-or-ref>` or `/autowork <project-or-gtm-session> <task_id> <full-base-branch-or-ref>`
  - store `review_base_ref` and `super_review_status_timeout_minutes: 20` in `autowork-log/config.yml`
  - save the report under `autowork-log/super-review.md` and require the report to state the exact diff base used
  - send findings to `pi-worker` for `/claude-super-fix`-style adjudication with room to disagree: `accept`, `accept_with_alternative_fix`, `dispute`, `skip`, `already_fixed`, `out_of_scope`, `follow_up`, `needs_user`
  - commit accepted code changes as `Super-review fix N`
  - rerun final checks after super-review fixes
  - send super-review fix commits to Claude for a normal scoped review, not another full super-review
  - do not rerun full super-review by default
- final manager-context production-readiness review gate:
  - stop at `ready_for_manager_final_review` after final checks, super-review, and scoped fix review pass
  - write `manager_review.md` with the manager-only context checklist
  - accept one structured `manager_reviews/manager_reviewN_findings.json` file through `autowork manager-review-fix <task_folder>`
  - automatically route manager findings to Pi, commit `Manager review fix N`, rerun full final checks, send a scoped Claude review, and loop on Claude findings
  - return to a fresh manager gate after Claude accepts; never auto-pass manager context after a fix
  - require pi-manager to decide whether the final result is production-ready if the user does not perform another review
  - mark complete only through `autowork manager-review-pass <task_folder>`
- deterministic specs for task resolution, state, status JSON, locks, pane discovery, doctor, first-cycle send/commit/review prompt flow, accepted-fix flow, debate flow, final-check fix flow, final super-review flow, super-review fix flow, automated manager-fix flow, manager-context final review, and final summary

## Intentional workflow boundaries

- `/autowork` can facilitate bounded Pi/Claude debate, but it must not adjudicate unresolved disagreement. If both agents still disagree after the configured round limit, it pauses for operator arbitration.

## Future improvements

- Update `/workit` to optionally create separate per-step files in addition to `steps.md`:
  - `steps.md` remains the overview/index.
  - `steps/step1.md`, `steps/step2.md`, etc. contain the exact executable scope for each step.
  - `/autowork` should prefer `steps/stepN.md` when present, and fall back to parsing `steps.md` headings for V1/backward compatibility.

## Test command

```sh
cd /Users/inseybo/.ai/skills-shared/autowork && rspec spec/autowork_spec.rb
```
