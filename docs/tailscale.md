# Tailscale on Squirrel and Oma

This file records only the local decisions that are not supplied by Tailscale documentation or the CLI. It intentionally contains no node addresses, tailnet name, account details, usernames, service mappings, credentials, or access policy.

## Ownership

This is the canonical cross-machine Tailscale reference. Both machines read the same file:

```text
Squirrel: ~/.dots/docs/tailscale.md
Oma:     ~/.dots/docs/tailscale.md
```

Author updates on Squirrel. Oma consumes the committed file through its pull-only `~/.dots` sync. Do not create another copy in `refs/dev-env` or `.omadots`.

Oma's broader machine setup remains owned by `~/.omadots/docs/setup.md`.

## Local decisions

- Squirrel uses the Homebrew command-line distribution.
- Oma uses the Arch package and systemd-managed services.
- Connection targets belong in each machine's untracked SSH configuration. Do not record tailnet addresses here.
- Squirrel's command-line installation uses a local `.ts.net` resolver file because split DNS was not configured automatically. Keep the resolver value aligned with Tailscale's current MagicDNS documentation rather than duplicating it here.
- Tailscale Serve mappings are runtime state. Inspect them with the CLI; do not duplicate their ports or targets in public documentation.
- When connectivity fails, inspect the initiating machine as well as the peer. A peer reported online does not prove that the initiating machine is authenticated.

## Agent rules

- Use configured SSH host aliases instead of embedding node addresses in commands or documentation.
- Never publish node addresses, tailnet DNS names, account identifiers, keys, ACLs, or private service mappings.
- Do not edit the shared `~/.dots` checkout on Oma.
- Keep machine-specific wiring in the owning machine repository and link back to this shared reference.

## Maintenance

Edit this file only on Squirrel. After review, commit and push the shared `dots` change. Oma receives it through the existing pull-only sync.

Use Tailscale's official documentation and local CLI help for installation, authentication, key expiry, MagicDNS, Serve, and troubleshooting commands. This file should contain only deviations and ownership decisions specific to this environment.
