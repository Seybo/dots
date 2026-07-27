# Temporary stubs and placeholders

Incremental stubs between implementation steps are encouraged — land a working skeleton first, fill in real behavior in a later step. The one hard rule: every temporary stub, placeholder, fake value, hardcoded shortcut, or not-yet-implemented path MUST carry this exact marker on its own comment line (in the file's comment syntax) directly above the placeholder, followed by a short note of what the real implementation is and which step adds it:

```text
!!!! SHOULD BE HANDLED/REMOVED BEFORE MERGE !!!!
```

Before declaring work merge-ready, `rg 'SHOULD BE HANDLED/REMOVED BEFORE MERGE'` must come back clean, or every remaining hit must be explicitly agreed to defer. A commit-gate hook also blocks `git commit` when the staged diff adds the marker. The marker is permission to stub between steps, not permission to merge a stub.
