---
name: web-search
description: Search the web through the isolated local Brave Search broker. Use when the user asks to search the web, research a topic, find current public information, compare options, or verify up-to-date external facts.
allowed-tools:
  - bash(/Users/inseybo/.dots/no_stow/bin/agent-brave-search *)
---

# Web search

Use this skill when web/current public information would materially improve the answer, especially when the user asks to:

- search the web
- research a topic
- find current public information
- compare tools, products, libraries, or approaches using current external sources
- verify up-to-date external facts

The user may also invoke it explicitly via:

```text
/skill:web-search <query>
```

## Behavior

1. Form a focused search query from the user's request.
2. Run the isolated agent-facing wrapper:

   ```sh
   /Users/inseybo/.dots/no_stow/bin/agent-brave-search --count 5 "<query>"
   ```

3. Use the returned search results to answer concisely.
4. Include source links from the search results when the answer relies on them.
5. If web search was used, start the final answer with this exact disclosure line:

   ```text
   🔴 **USED WEB SEARCH**
   ```

   This is intentionally uppercase and bold. The red circle is the portable red marker because not every agent UI renders colored Markdown/HTML text.

The wrapper prints an audit marker to stderr for every real search:

```text
WEB_SEARCH_USED provider=brave count=<N> query="<query>"
```

That marker is intentional. Do not hide, suppress, or redirect it.

## Options

If the user asks for a specific number of results, pass `--count N`, with `N` between 1 and 10.

If the user asks for raw results or JSON, pass `--json`; stdout remains sanitized JSON and the audit marker still goes to stderr.

Do not use this skill for local repo/file questions where local inspection is enough. Prefer dedicated documentation tools/skills when the user specifically asks for library/API docs and those tools are available.

## Safety rules

Do not run or suggest running:

- `agent-brave-search-admin`
- `rage`
- `rage-keygen`
- `unrage_file`
- `sudo`
- commands that read `/usr/local/etc/agent-broker/`
- commands that inspect the broker LaunchDaemon or installed broker files unless the user is explicitly debugging the broker itself

Never ask for, print, infer, or expose the Brave API key. The only supported access path is the safe wrapper above.

If the wrapper fails, report the error and suggest checking `refs/dev-env/tools/agent-broker.md` for setup/troubleshooting.
