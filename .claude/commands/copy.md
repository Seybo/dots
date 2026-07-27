---
description: Save an artifact from the conversation to the macOS clipboard via pbcopy. Args are always a natural-language SELECTOR (e.g. "last sql query", "bash ls command"). No args = most recent one-liner.
---

# /copy

Save an artifact from the current conversation to the macOS clipboard using `pbcopy`.

## Invocation

The argument is **always a selector** describing what to find in the conversation — never literal text to copy verbatim. To copy text that hasn't appeared in the conversation, paste it inline first or use `pbcopy` directly in a shell.

| Invocation | Meaning |
|---|---|
| `/copy` | The most recent one-line copy-paste artifact (single-line code block intended for pasting into a REPL or terminal). |
| `/copy last sql query` | The most recent SQL statement in the conversation. Prefer the one-line form if both multiline and one-line variants exist. |
| `/copy bash ls command` | The most recent Bash command starting with `ls` in the **latest agent message**, not the whole conversation. |
| `/copy last python snippet` | The most recent Python code block. |
| `/copy the curl call I just got` | The most recent `curl` invocation, latest agent message. |
| `/copy <other selector>` | Best-effort interpretation. Identify the matching artifact, ask for clarification only if ambiguous between two recent candidates. |

Recency wins ties. "Latest agent message" wins over older messages when the selector mentions "just", "this", or sounds present-tense.

## Behavior

1. Parse the selector and locate the artifact in the conversation. If multiple plausible matches exist, briefly state both and ask which (don't guess silently).
2. **Strip a trailing newline before copying.** Bash and SQL REPLs treat a trailing `\n` as "execute," so a clipboard ending in `\n` would auto-fire on paste — rarely what you want.
3. Pipe the artifact through `pbcopy` using a quoting-safe method (see Implementation below).
4. Read back via `pbpaste` to verify, then print a one-line confirmation.

## Implementation

Naive `printf '%s' '...' | pbcopy` breaks on embedded single quotes, backticks, or `$` characters. Use one of:

- **Python via stdin** (handles any byte sequence):

  Multiline form (readable):
  ```bash
  python3 -c "import sys, subprocess; subprocess.run(['pbcopy'], input=sys.stdin.read(), text=True)" <<'CLIPBOARD_EOF'
  <text>
  CLIPBOARD_EOF
  ```

  One-line form (paste-ready):
  ```bash
  python3 -c "import sys, subprocess; subprocess.run(['pbcopy'], input=sys.stdin.read(), text=True)" <<'CLIPBOARD_EOF'
<text>
CLIPBOARD_EOF
  ```

- **Temp file**:
  ```bash
  cat > /tmp/_copy_payload <<'CLIPBOARD_EOF'
  <text>
  CLIPBOARD_EOF
  pbcopy < /tmp/_copy_payload && rm /tmp/_copy_payload
  ```

The single-quoted heredoc delimiter (`'CLIPBOARD_EOF'`) disables shell expansion inside the payload — variables, backticks, and `$` stay literal.

## Output

Print one line on success:

```
[copied to clipboard, N bytes] <first 80 chars>...
```

Truncate `<first 80 chars>` with `...` only if the artifact is longer than 80 chars. Otherwise show the whole thing.

## Failure modes

- `pbcopy` is macOS-only. On Linux, fall back to `xclip -selection clipboard` (X11) or `wl-copy` (Wayland). Print a one-line warning if the platform isn't macOS.
- If no recent matching artifact exists, say so explicitly: `no <selector type> found in recent messages`. Don't fabricate something to copy.
- If the selector is genuinely ambiguous (two plausible candidates), list both with a short preview and ask which.
