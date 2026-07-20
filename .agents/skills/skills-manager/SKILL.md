---
name: skills-manager
description: Manage external Claude/Codex/Pi skills/plugins. Audits normal external skills with NVIDIA SkillSpector, Cisco skill-scanner, and Sentry skill-scanner before install/update.
---

# Skills manager

External skill content is untrusted until freshly audited.

Auditors live at:

- `.ai/external-skills/skillspector/`
- `.ai/external-skills/cisco-skill-scanner/`
- `.ai/external-skills/sentry-skill-scanner/`

## Files

- Manifest: `.ai/external-skills/external-skills.yml`
- Managed sources: `.ai/external-skills/<name>/`
- Audits: `.ai/external-skills/audits/<name>/<timestamp>-<head>/`
- State: `.ai/external-skills/state.yml`
- CLI: `.agents/skills/skills-manager/bin/skills-manager`

## Rules

- Do not install/update normal external skills directly with `claude`, `codex`, plugin commands, manual copies, or ad-hoc scripts.
- Normal skills: audit with all three auditors before install/update.
- Auditor skills are trust roots; `skills-manager` does not audit them.
- Update auditor skills one at a time.
- Block normal skill install/update on auditor errors, dirty/missing checkouts, High/Critical findings, or `DO_NOT_INSTALL`.
- Warnings block unless the user explicitly approves `--allow-warnings`.

## Manifest shape

```yaml
auditors:
  skillspector:
    origin: https://github.com/NVIDIA/skillspector.git
    ref: main
    adapter: skillspector

  cisco-skill-scanner:
    origin: https://github.com/cisco-ai-defense/skill-scanner.git
    ref: main
    adapter: cisco_skill_scanner

  sentry-skill-scanner:
    origin: https://github.com/getsentry/skills.git
    ref: main
    adapter: sentry_skill_scanner
    source_path: skills/skill-scanner

skills: {}
```

Paths are derived from the entry name. `source_path` is exported to `.ai/external-skills/<name>/` through a temporary clone that is removed after sync.

## Commands

```bash
.agents/skills/skills-manager/bin/skills-manager list
.agents/skills/skills-manager/bin/skills-manager status
.agents/skills/skills-manager/bin/skills-manager --dry-run sync <name>
.agents/skills/skills-manager/bin/skills-manager sync <name>
.agents/skills/skills-manager/bin/skills-manager audit <name>
.agents/skills/skills-manager/bin/skills-manager install <name>
.agents/skills/skills-manager/bin/skills-manager update <name>
.agents/skills/skills-manager/bin/skills-manager audit-plan <name>
```

## Bootstrap auditors

```bash
.agents/skills/skills-manager/bin/skills-manager --dry-run sync
.agents/skills/skills-manager/bin/skills-manager sync
.agents/skills/skills-manager/bin/skills-manager install skillspector
.agents/skills/skills-manager/bin/skills-manager install cisco-skill-scanner
.agents/skills/skills-manager/bin/skills-manager install sentry-skill-scanner
```

## Add/update a normal skill

1. Add/update `.ai/external-skills/external-skills.yml`.
2. Run:
   ```bash
   .agents/skills/skills-manager/bin/skills-manager --dry-run sync <name>
   .agents/skills/skills-manager/bin/skills-manager sync <name>
   .agents/skills/skills-manager/bin/skills-manager audit <name>
   .agents/skills/skills-manager/bin/skills-manager install <name>
   ```

For updates, use:

```bash
.agents/skills/skills-manager/bin/skills-manager update <name>
```
