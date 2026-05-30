# Temporary stubs and placeholders

Temporary stubs are fine and even **encouraged** when building something across multiple
implementation steps. Landing a working skeleton first and filling in real behavior in a later
step — rather than building everything at once — keeps each step small, reviewable, and shippable.

The one hard rule: every temporary stub, placeholder, fake value, hardcoded shortcut, or
"fill this in later" MUST carry this exact marker, on its own comment line directly above the
placeholder code:

```text
!!!! SHOULD BE HANDLED/REMOVED BEFORE MERGE !!!!
```

This applies to anything that must not survive into a merged change: not-yet-implemented method
bodies, stubbed/fake return values, hardcoded data standing in for real input, skipped
validation, a `raise 'NOT_IMPLEMENTED'`, a correctness-blocking TODO, and similar.

## Why

Incremental stubs keep steps small, but a placeholder that slips silently into a merge becomes a
latent bug or a correctness/security gap. The loud, uniform marker makes every such spot
greppable and impossible to miss in review.

## How to apply

- Put the marker on its own comment line immediately above the placeholder, in the file's comment
  syntax (`#`, `//`, `<!-- -->`, etc.).
- Follow it with a short line stating what the real implementation should be and which step adds it.
- Before declaring work merge-ready, grep for the marker (`rg 'SHOULD BE HANDLED/REMOVED BEFORE MERGE'`)
  and confirm none remain — or that any remaining ones are explicitly agreed to defer.
- The marker is permission to stub *between steps*, not permission to merge a stub. Remove or
  implement it before the change is considered done.
