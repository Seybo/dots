# Multiline + one-line forms for REPL/copy-paste artifacts

For each copy-pasteable artifact that spans multiple lines (shell command with `\` continuations, SQL query, JSON snippet), provide that same artifact twice: the readable multiline code block, exactly one empty line, then a one-line code block. No labels or commentary between the two blocks. The one-line form pastes into a REPL as a single history entry, so it can be recalled and edited as a unit.

- Match the one-liner to the REPL the user is already in: bare SQL inside `psql`/`sqlite3`, bare command for shell, bare `GET key` for redis-cli — never a shell wrapper (`sqlite3 file.db "..."`) that would nest a REPL. Default assumption: the user is inside the relevant REPL; use the wrapped form only for scripts/CI one-offs, and say so.
- One artifact per pair. Never join unrelated commands with `&&`/`;` to make a one-liner.
- If the entire response contains exactly one command artifact, also copy the one-line form to the macOS clipboard via `pbcopy` (strip the trailing newline so pasting doesn't auto-execute) and end the response with `[copied to clipboard]`. With multiple artifacts, copy nothing — the user picks with `/copy <selector>`.
- Applies to shell/SQL/similar REPL targets only — not to Python/Ruby/other languages where one-lining would be unreadable or invalid.
