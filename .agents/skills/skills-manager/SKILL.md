---
name: skills-manager
description: Manage external Claude/Codex/Pi skills/plugins. Enforces fresh audits with NVIDIA SkillSpector, Cisco skill-scanner, and Sentry skill-scanner before install/update.
---

# Skills manager

External skill content is untrusted until freshly audited.

## Files

- Manifest: `.ai/external-skills/external-skills.yml`
- Checkouts: `.ai/external-skills/checkouts/<name>/`
- Audits: `.ai/external-skills/audits/<name>/<timestamp>-<head>/`
- State: `.ai/external-skills/state.yml`
- CLI: `.agents/skills/skills-manager/bin/skills-manager`

## Rules

- Do not install/update external skills directly with `claude`, `codex`, plugin commands, manual copies, or ad-hoc scripts.
- `install` always runs a fresh audit first.
- `update` syncs, audits, then installs.
- Normal skills: audit with all three auditors.
- Auditor skills: audit with the other two auditors; no self-audit.
- Update auditor skills one at a time.
- Block on auditor errors, dirty/missing checkouts, High/Critical findings, or `DO_NOT_INSTALL`.
- Warnings block unless the user explicitly approves `--allow-warnings`.

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

Each auditor install is audited by the other two auditors.

## Add/update a skill

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
