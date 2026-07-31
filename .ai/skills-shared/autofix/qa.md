# Autofix QA

Use this process before every manual Autofix QA round.

## Agent-owned setup

Before asking the operator to prepare anything, the agent owns all deterministic QA setup:

- Derive Manager's current tmux window from dynamic `$TMUX_PANE` and restrict all participant setup and routing to that exact resolved window. Never use `tmux list-panes -a`, search other windows or sessions, hardcode tmux IDs, or fall back outside the resolved window. Fail when a required participant pane is absent there.
- Preserve every pane's existing shell, process lifecycle, and layout. Never terminate, replace, respawn, recreate, reset, or close a pane, window, session, shell, or pane process. Prohibited examples include `respawn-pane`, `respawn-window`, `kill-pane`, `kill-window`, and `kill-session`, plus any command, option, signal, or workaround with an equivalent effect.
- Never launch Pi as a replacement for the pane shell through `exec`, a tmux direct-command argument, or an equivalent mechanism. Pi must run as a child of the existing shell so exiting Pi returns to that shell.

- Create or prepare the target checkout, branch, fixture files, Git configuration, remotes, and base refs. Create temporary QA checkouts outside tracked repositories, such as under `/tmp`; never place them inside `.dots` or another checkout where they could be committed accidentally.
- Create the feature-specific test data.
- Put the Autofix runtime database into the state required by the QA scenario.
- Create or remove temporary result files and other QA artifacts as required.
- Keep participant panes and Pi sessions in their normal working directory, assumed to be `.dots`. Put the target checkout only in the Work Cycle's authoritative `project_path`; participants use that path explicitly for every operation. Do not change pane cwd or restart Pi for QA. State the target checkout path.

Do not include agent-owned setup in the operator prerequisite list.

## Operator prerequisite procedure

1. Identify only the operator-controlled environment required by the feature being tested.
2. Show those prerequisites as one numbered list so the operator can reference items by number.
3. Include a source prerequisite only when that source boundary is part of the feature under test. For example, require clipboard state only when testing clipboard extraction, and GitHub state only when testing GitHub collection.
4. End with `Confirm when this QA environment is ready.`
5. Wait for the operator's confirmation.
6. Trust the confirmation. Do not inspect tmux panes, pane titles, current commands, sessions, windows, working directories, clipboard contents, Git status, authentication, or other prerequisite state.
7. Start the QA flow directly after confirmation.

If QA fails because a prerequisite was not met, report it and stop. Do not add doctor behavior or preflight checks.

## Standard operator prerequisites

Include only the items used by the current feature:

- Required participant panes exist in the current tmux window, with each required title appearing exactly once: `agent-manager`, `agent-worker`, or `agent-reviewer`.
- Required panes run Pi from their normal `.dots` working directory. Autofix supplies and owns the separate target checkout through Work Cycle `project_path`.
- Required Pi sessions have loaded the current shared rules, skill, prompt, and permissions.
- Participant panes contain no extra instructions; Autofix sends only `AutoFixCycle <id>`.
- No unrelated work will modify the target checkout, Autofix state, result files, or participant panes during QA.
- The operator is available for expected permission prompts.

## Feature-specific operator prerequisites

Add an item only when the feature under test requires operator-controlled state that the agent cannot prepare.

Examples:

- Clipboard extraction QA: the clipboard contains the intended review and will remain unchanged until Manager reads it.
- GitHub collection QA: the current branch has the intended pull request and `gh` is authenticated.
- Independent Reviewer QA: an `agent-reviewer` pane is available.

Do not include unrelated upstream or downstream workflow prerequisites merely to reach the feature under test. Prepare those states deterministically instead.

## Outcome verification

Readiness confirmation replaces setup inspection, not QA assertions. After QA starts, inspect only the workflow outputs, Git changes, Autofix records, and result files needed to verify the current task's acceptance criteria.
