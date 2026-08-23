# GTM project rules (dev-local)

Personal, dev-specific rules for the ShakaCode GTM project. Loaded via a gitignored
`CLAUDE.local.md` pointer in each gtm checkout (`$DEV_ROOT/projects/shaka/gtm/<Nth>/`);
the pointer file contains a single `@~/.ai/rules/gtm.md` import line. Team-shared
conventions belong in the repo's committed `CLAUDE.md`/`AGENTS.md`, not here.

The shared Ruby/Rails conventions in `ruby-general.md` apply (loaded globally).

- The registered project id is `shaka_gtm` (see `~/.ai/skills-shared/components/projects.yml`);
  task folders live under `$DEV_ROOT/_tasks/shaka_gtm/`. Branches carry an `sc-<digits>`
  Shortcut story segment, and branch slugs come from the Shortcut story name.

<!-- Add gtm-specific non-obvious gotchas here as they come up; keep this file short. -->
