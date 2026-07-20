---
name: skills-manager
description: Manage external Claude and Pi skills/plugins from .ai/external-skills. Audits normal external skills with SkillSpector, Cisco skill-scanner, and Sentry skill-scanner before install/update.
---

# Skills manager

External skill content is untrusted until freshly audited.

## Paths

- Manifest: `.ai/external-skills/external-skills.yml`
- Managed sources: `.ai/external-skills/<name>/`
- Audits: `.ai/external-skills/audits/<name>/<timestamp>-<head>/`
- State: `.ai/external-skills/state.yml`
- CLI: `.agents/skills/skills-manager/bin/skills-manager`

## Rules

- Use `skills-manager`; do not install normal external skills directly with `claude`, `pi`, plugin commands, manual copies, or ad-hoc scripts.
- Normal skills are audited by all three auditors before install/update.
- Auditor skills are trust roots and are not audited by this manager.
- Block on auditor errors, High/Critical findings, `DO_NOT_INSTALL`, dirty checkouts, or missing checkouts.
- Warnings require explicit user approval via `--allow-warnings`.
- Do not manage Codex plugins from this skill.

## Install from URL

`install <url>` is an agent workflow. The Ruby CLI installs manifest names only.

1. Name = repo basename.
2. Inspect the repo with a direct GitHub read or a temporary clone under `.ai/external-skills/.tmp/`; remove any temp clone.
3. Write/overwrite `skills.<name>` in the manifest:
   - `origin`: URL
   - `ref`: `main`
   - no `source_path`
   - `install`: detected Claude/Pi targets
4. Detect targets:
   - `.claude-plugin/marketplace.json` or `.claude-plugin/plugin.json` => `claude_plugin`
   - root `SKILL.md` or `skills/*/SKILL.md` => `pi_install`
5. If no Claude or Pi target is found, stop.
6. Run:

```bash
.agents/skills/skills-manager/bin/skills-manager sync <name>
.agents/skills/skills-manager/bin/skills-manager --dry-run install <name>
.agents/skills/skills-manager/bin/skills-manager install <name>
```

No target prompt. No custom names. No scoped installs. No Codex. No `source_path` for normal URL installs.

## Install/update manifest entry

For an existing manifest name, run:

```bash
.agents/skills/skills-manager/bin/skills-manager --dry-run sync <name>
.agents/skills/skills-manager/bin/skills-manager sync <name>
.agents/skills/skills-manager/bin/skills-manager --dry-run install <name>
.agents/skills/skills-manager/bin/skills-manager install <name>
```

`install` audits normal skills first, then applies configured install actions.

## Auditor bootstrap

```bash
.agents/skills/skills-manager/bin/skills-manager sync
.agents/skills/skills-manager/bin/skills-manager install skillspector
.agents/skills/skills-manager/bin/skills-manager install cisco-skill-scanner
.agents/skills/skills-manager/bin/skills-manager install sentry-skill-scanner
```

## Other commands

```bash
.agents/skills/skills-manager/bin/skills-manager list
.agents/skills/skills-manager/bin/skills-manager status
.agents/skills/skills-manager/bin/skills-manager audit <name>
.agents/skills/skills-manager/bin/skills-manager audit-plan <name>
.agents/skills/skills-manager/bin/skills-manager update <name>
```
