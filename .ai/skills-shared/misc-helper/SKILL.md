---
name: misc-helper
description: Run small personal helper utilities from one command namespace. Command-only skill. Invoke via /misc-helper <helper>, currently supports davinci-kill for terminating stuck DaVinci Resolve app processes.
allowed-tools:
  - "bash(/Users/inseybo/.ai/skills-shared/misc-helper/scripts/misc-helper *)"
---

# Misc Helper

This is a command-only skill for small personal helper utilities that do not deserve separate skills.

## Invocation

Use only:

```text
/misc-helper <helper>
```

Currently supported:

```text
/misc-helper davinci-kill
```

## Behavior

1. Parse the first argument as the helper name.
2. Run only the matching helper listed below.
3. If the helper is unknown or missing, show the available helpers and stop.
4. Do not invent ad-hoc helpers. Add new helpers by updating this skill and `scripts/misc-helper`.

## Helpers

### davinci-kill

Force-quit stuck DaVinci Resolve app processes.

Run:

```bash
/Users/inseybo/.ai/skills-shared/misc-helper/scripts/misc-helper davinci-kill
```

The script:

- finds only the Resolve app executable and its bundled IOXPC helper by exact app paths;
- sends SIGTERM first;
- sends SIGKILL only to remaining matching processes;
- verifies no matching Resolve app processes remain.
