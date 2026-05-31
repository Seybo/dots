# Agent operating rules

General agent workflow and command-use rules. These are language- and project-neutral unless a project's local instructions override them.

## Command efficiency

- Prefer targeted, low-latency commands over broad scans or mass replacements. Scope `rg`, tests, RuboCop, and file edits to the smallest relevant paths first; run full checks only at step boundaries or when needed.
- Avoid broad `perl -pi`, `sed -i`, or repo-wide replacements when strings overlap (for example rename/revert work). Use precise `edit` replacements or a small script with explicit file lists and post-change verification.
- Before running a command that may take more than a few seconds, state what it will do and why. After it returns, immediately summarize the result and next action.
- For numbered file snippets, prefer the read tool or `nl -ba <file> | sed -n '<range>p'`; avoid ad-hoc `awk` line-numbering commands when `nl -ba` does the same job.
