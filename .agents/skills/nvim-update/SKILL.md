---
name: nvim-update
description: Audit the local Neovim config under .config/nvim and report whether bumping lazy.nvim plugins from the pinned lazy-lock.json commits to current upstream is safe. Distinguish breaking changes, deprecations, recommendations, and ambiguous findings. Report only; never edit files.
---

# Nvim Update

Use this skill only for the command-style invocation:

- `/nvim-update`

This skill is repo-specific to `~/.dots` and audits only `~/.dots/.config/nvim`.

## Goal

Tell the user whether it is safe to sync/update Neovim plugins themselves.

The skill must:
- inspect the user's actual Neovim config under `.config/nvim`
- inspect `lazy-lock.json`
- inspect each declared plugin's current upstream state
- determine whether bumping from the pinned commit to current upstream is safe for this exact config
- produce a full report

The skill must not:
- edit files
- update plugins
- update lockfiles
- create files
- suggest unrelated refactors or style changes

## Safety categories

Use these categories exactly and keep them distinct:

- **Breaking**: a current upstream change is likely to make this config stop working or behave incorrectly after sync
- **Deprecations**: not breaking now, but upstream marks something as deprecated or on a removal path relevant to this config
- **Recommendations**: optional upstream-advised migration or cleanup that is not required for correctness right now
- **Ambiguous**: uncertain or partially documented risk that may matter for this config and should be reviewed manually

Definition of **safe**:
- Safe means **no known breaking changes affecting this config**
- Deprecations and recommendations do not make the sync unsafe by themselves; they should be reported as comments

## Scope

Inspect only `.config/nvim`, including:
- `init.lua`
- `lazy-lock.json`
- `lua/plugins/**`
- any modules referenced from plugin specs or core config under `.config/nvim`

Do not inspect other parts of the repo unless a file under `.config/nvim` explicitly depends on them.

Ignore plugins present in `lazy-lock.json` but not actually declared in the current Neovim plugin specs.

## Required workflow

1. **Inventory local config**
   - Read `.config/nvim/init.lua`
   - Read `.config/nvim/lua/config/lazy.lua`
   - List and read `.config/nvim/lua/plugins/**`
   - Read any referenced local modules needed to understand plugin usage
   - Read `.config/nvim/lazy-lock.json`

2. **Build the declared plugin set**
   - Extract every actually declared plugin from the lazy specs
   - Map each declaration to:
     - repo slug
     - local file path
     - lockfile key if present
     - relevant local config usage
   - Resolve dependencies declared in plugin specs when they are real plugins in use

3. **Cross-check lockfile presence**
   - For each declared plugin, confirm whether there is a corresponding lockfile entry
   - Ignore lockfile-only entries that are no longer declared
   - If a declared plugin has no lock entry, note it as ambiguous and continue

4. **Check upstream current state for every declared plugin**
   For each declared plugin, compare:
   - pinned commit/version from `lazy-lock.json`
   - current upstream default branch / latest release / current docs

   Prefer official sources in this order:
   1. release notes / changelog
   2. README migration notes
   3. official docs website
   4. issue/discussion only if official docs are missing and the issue is authoritative enough

   Extract changes since the pinned commit that are relevant to the user's config.

5. **Match upstream changes against actual local usage**
   - Do not flag a finding just because upstream changed
   - Only mark **Breaking** when the local config actually uses the changed, removed, renamed, or behavior-sensitive API/path/option/pattern
   - Always inspect even minimally configured plugins; indirect breakage via dependencies or ecosystem changes can matter
   - Consider transitive breakage from Neovim core changes or companion plugins when materially relevant

6. **LSP-specific guardrails for this repo**
   If `.config/nvim/lua/plugins/lsp.lua` still uses:
   - `vim.lsp.config()`
   - `vim.lsp.enable()`
   - `require('mason-lspconfig').setup({ automatic_enable = false })`

   then:
   - do not recommend `setup_handlers` unless upstream truly requires it
   - do not recommend enabling automatic server setup unless upstream truly requires it
   - do not suggest changing `automatic_enable = false` unless it is actually broken upstream
   - do not suggest splitting the file or restructuring the LSP setup

   For `mason.nvim`, `mason-lspconfig.nvim`, `nvim-lspconfig`, `nvim-cmp`, `mason-tool-installer`, and related LSP pieces, be especially strict about distinguishing:
   - hard breakage
   - deprecation only
   - optional recommendation

7. **Prepare proposed follow-up changes when needed**
   - Never edit files
   - If a sync would require config changes, provide:
     - exact file path
     - precise minimal proposed edit description
     - why it is needed
   - Keep proposed changes behavior-preserving and surgical
   - Do not invent new files
   - Do not add new plugins
   - Do not add unrelated options

8. **Produce the final report**
   Report on all declared plugins, not only the ones with findings.

## Output format

Start with a 3-5 line summary.

Then include a top-level verdict as one of:
- **Safe to sync now**
- **Sync is safe with follow-up changes**
- **Sync not recommended yet**

Then list every declared plugin with this structure:

```md
### <plugin>
- **Pinned:** <commit/version>
- **Current upstream:** <release/branch/commit if known>
- **Status:** Safe | Breaking | Deprecations | Recommendations | Ambiguous | Mixed
- **Config file(s):** <paths>

**Breaking**
- None

**Deprecations**
- None

**Recommendations**
- None

**Ambiguous**
- None
```

Rules:
- Every declared plugin must appear in the report
- Use `None` when a category has no findings
- If a plugin is fully safe, still include it and say so
- For any needed follow-up, include:
  - `**Proposed follow-up:**`
  - exact file path
  - minimal change description
  - reason
- Do not output full replacement files
- Do not output illustrative snippets unless a tiny snippet is the only precise way to name the change

## Citation rules

- Cite sources for every **Breaking**, **Deprecations**, and **Ambiguous** finding
- Citations for explicit **Safe** conclusions are optional
- Prefer official upstream URLs
- Cite the exact upstream document used: release notes, changelog entry, migration note, README section, or official docs page
- If relying on a non-official source for ambiguity, say so explicitly

## Investigation rules

- Be thorough for all plugins, no exceptions
- Do not assume a "typical" Neovim setup; confirm from the repo
- Do not claim breakage without matching it to actual local usage
- If upstream information is unclear, put it under **Ambiguous** rather than overstating confidence
- If multiple plugins interact, explain the interaction briefly under the affected plugin entries
- Keep the tone direct, minimal, and confident

## Practical notes

- Use local file reads first to understand the actual config shape
- For upstream checks, use official docs and repository pages
- Since the goal is safe syncing, focus on delta from pinned commit to current upstream
- This is an audit skill, not an implementation skill

## Example invocation

```text
/nvim-update
```

Treat this as an execution request. Do not ask for confirmation before starting the audit.

## Expected report skeleton

```md
Summary:
- Audited `.config/nvim` plugin declarations and `lazy-lock.json`
- Compared pinned plugin commits against current upstream state
- Checked each upstream change against actual local config usage
- Result: <Safe to sync now | Sync is safe with follow-up changes | Sync not recommended yet>

## Verdict
**<Safe to sync now | Sync is safe with follow-up changes | Sync not recommended yet>**

### <plugin-1>
- **Pinned:** <commit/version>
- **Current upstream:** <release/branch/commit if known>
- **Status:** <Safe | Breaking | Deprecations | Recommendations | Ambiguous | Mixed>
- **Config file(s):** <path(s)>

**Breaking**
- None

**Deprecations**
- None

**Recommendations**
- None

**Ambiguous**
- None

### <plugin-2>
- **Pinned:** <commit/version>
- **Current upstream:** <release/branch/commit if known>
- **Status:** <Safe | Breaking | Deprecations | Recommendations | Ambiguous | Mixed>
- **Config file(s):** <path(s)>

**Breaking**
- <finding>
  - **Proposed follow-up:**
    - **File:** `.config/nvim/<path>`
    - **Change:** <minimal proposed edit description>
    - **Reason:** <why this is needed>
  - **Source:** <official upstream citation>

**Deprecations**
- None

**Recommendations**
- None

**Ambiguous**
- None
```
