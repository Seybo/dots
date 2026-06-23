# Agent operating rules

General agent workflow and command-use rules. These are language- and project-neutral unless a project's local instructions override them.

## Pi slash commands and skills

When the user asks about a Pi "skill" or `/command`, treat that as any Pi slash command, not only an Agent Skill from `<available_skills>`. Pi slash commands can come from prompt templates (`/name`), Agent Skills (`/skill:name`), extension commands, or built-in commands. If a command appears in Pi autocomplete, it exists even when it is not listed in `<available_skills>`. Do not say a `/command` is unavailable solely because it is absent from `<available_skills>`; ask the user to run it or check prompt templates/commands if needed.

## Command efficiency

- Prefer targeted, low-latency commands over broad scans or mass replacements. Scope `rg`, tests, RuboCop, and file edits to the smallest relevant paths first; run full checks only at step boundaries or when needed.
- Avoid broad `perl -pi`, `sed -i`, or repo-wide replacements when strings overlap (for example rename/revert work). Use precise `edit` replacements or a small script with explicit file lists and post-change verification.
- Before running a command that may take more than a few seconds, state what it will do and why. After it returns, immediately summarize the result and next action.
- To avoid avoidable Pi permission prompts, do not send multiline bash payloads when the same work can be done with separate tool calls or one safe line joined with `;` / `&&`. Pi permission checks handle pipelines/segments better than newline-separated pasted blocks.
- For numbered file snippets, prefer the read tool or `nl -ba <file> | sed -n '<range>p'`; avoid ad-hoc `awk` line-numbering commands when `nl -ba` does the same job.
