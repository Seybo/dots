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
- write `final_checks.md` and `final_summary.md`
- deterministic specs for task resolution, state, status JSON, locks, pane discovery, doctor, first-cycle send/commit/review prompt flow, accepted-fix flow, debate flow, final-check fix flow, and final summary

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
