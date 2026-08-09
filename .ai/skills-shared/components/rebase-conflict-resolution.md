# Shared rebase conflict resolution

This component is authoritative for Manager handling after an Autoimplement or
Autofix rebase helper reports a conflict. The invoking skill supplies its exact
identity control line and continuation command. Retain the identity, exact
target ref, and full target SHA for the current invocation. Do not display the
control lines or persist them.

For every current unmerged conflict occurrence:

- inspect the unmerged diff, Git base/ours/theirs stages, relevant surrounding
  code, and affected behavior;
- treat the same path conflicting while a later commit replays as another
  occurrence;
- resolve an unambiguous conflict directly and retain its path, short problem,
  and short applied resolution;
- for ambiguity, begin the complete turn with `[MM_NTF]`, show the conflicting
  code and relevant context, recommend one resolution, and ask one precise
  question before editing.

After resolving every current conflict, run only the continuation helper command
specified by the invoking skill. Ruby stages and continues the native rebase.
Manager must not run `git add`, `git rebase`, or edit Task config or SQLite
directly.

If continuation reports another conflict, repeat and retain every resolution in
chronological order. On success, append:

```text
Resolved conflicts:
- `<path>`: <short conflict description>; <short applied resolution>
```

Include every conflict occurrence. Surface non-conflict helper failures
unchanged, with `[MM_NTF]` first when operator action is required. Leave an
in-progress rebase and metadata unchanged on conflict or failure. Never switch
branches, push, start a Work Cycle, expose Work Cycle commit SHAs, or resume
normal orchestration automatically.

Interrupted continuation has no recovery state. Begin with `[MM_NTF]`, tell the
operator to run `git rebase --abort` manually, then invoke the original explicit
rebase operation again. Manual `git rebase --continue` is unsupported.
