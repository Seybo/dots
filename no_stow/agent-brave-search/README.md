# Agent Brave Search broker

This exposes Brave Search to agents without exposing the Brave API key to the agent process.

## Security model

- The API key is encrypted at rest with `rage` using age identity-key mode, not passphrase mode.
- Decryption uses the private age identity file; there is no passphrase prompt after reboot or per search.
- A dedicated macOS service user, `_agentbroker`, owns protected broker material. The user name is intentionally generic so future agent capabilities can reuse the same isolated identity.
- The Brave Search capability stores its age identity and encrypted API key under `/usr/local/etc/agent-broker/brave-search/` with `0400` file permissions.
- Agents run as the normal user and only get access to the Unix socket at `/var/tmp/agent-broker/brave-search.sock`.
- The broker decrypts the key in memory and calls only the Brave web search endpoint.
- The wrapper returns sanitized search results only.
- This prevents accidental key disclosure and blocks same-user file reads of the key material. It does not protect against root, sudo approval granted to an agent, or edits to the installed root-owned daemon files.

## Install

Run these yourself, not from an agent session:

```sh
cd ~/.dots
sudo no_stow/bin/agent-brave-search-admin install
sudo no_stow/bin/agent-brave-search-admin set-key
sudo no_stow/bin/agent-brave-search-admin load
```

`set-key` prompts for the Brave API key and encrypts it in memory; it does not write plaintext to disk.

## Use

```sh
/Users/inseybo/.dots/no_stow/bin/agent-brave-search --health
/Users/inseybo/.dots/no_stow/bin/agent-brave-search --count 5 "ruby net/http timeout docs"
/Users/inseybo/.dots/no_stow/bin/agent-brave-search --json "ruby net/http timeout docs"
```

Only `agent-brave-search` is allowlisted for agents. `agent-brave-search-admin` is intentionally not allowlisted.

## After laptop restart

No manual action should normally be required after restart. The LaunchDaemon starts the broker automatically at boot.

Verify with:

```sh
/Users/inseybo/.dots/no_stow/bin/agent-brave-search --health
```

If needed, restart manually:

```sh
cd ~/.dots
sudo no_stow/bin/agent-brave-search-admin load
```

You do not need to re-enter the Brave API key unless you intentionally rotate/delete it.

## Manage

```sh
sudo no_stow/bin/agent-brave-search-admin status
sudo no_stow/bin/agent-brave-search-admin unload
sudo no_stow/bin/agent-brave-search-admin load
sudo no_stow/bin/agent-brave-search-admin set-key
```

## Installed paths

- Broker script: `/usr/local/libexec/agent-broker/brave-search/brave_search_broker.rb`
- LaunchDaemon: `/Library/LaunchDaemons/local.agent-broker.brave-search.plist`
- Secret material: `/usr/local/etc/agent-broker/brave-search/`
- Socket: `/var/tmp/agent-broker/brave-search.sock`
- Logs: `/var/log/agent-broker/brave-search/`
