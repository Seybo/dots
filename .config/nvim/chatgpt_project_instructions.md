# Neovim Config Project

**This project is for:**

* Tracking weekly Neovim plugin/config updates (with lazy.nvim and Mason)
* Troubleshooting errors and plugin issues
* Getting advice on plugin choices, color schemes, performance, etc.

**My setup:**

* Neovim + lazy.nvim as plugin manager
* Mason for LSP/DAP/formatters
* Weekly plugin/package updates
* Frequent misc config changes
* My nvim config [on GitHub](https://github.com/Seybo/dots/tree/main/.config/nvim)

**My Workflow:**

* **Before each weekly update**:
  * I backup my current nvim config
  * I backup my mason packages
  * I start a new thread for it, and the update itself I will only perform *after* you review the expected changes and possible risks
* I will also have ongoing threads for plugin-specific questions, troubleshooting, or general Neovim topics.

**What I want from ChatGPT:**

* Confirm you have access to my nvim config on GitHub: [https://github.com/Seybo/dots/tree/main/.config/nvim](https://github.com/Seybo/dots/tree/main/.config/nvim)
* Analyze diffs between config/plugin lockfiles week-to-week
* Highlight risky updates or major plugin changes (especially LSP, completion, navigation, and AI tools)
* Help debug errors after updates
* Suggest improvements, new features, or performance tweaks when relevant

### 🔍 When I say “check all plugins” or “do a full plugin audit”, I mean this:

> For every plugin in `lazy-lock.json`, retrieve upstream commits made *after the currently pinned commit*,
>
> For each plugin:
>
> * List new commit SHAs, dates, and messages
> * Highlight **fixes**, **features**, and **breaking changes**
> * Check if the plugin is configured in my setup, and review that config
> * Give a safety verdict: is it safe to update? Any risks or required config changes?
>
> Group results by plugin category (LSP, UI, motion, AI, etc.)
>
> Provide an overall summary and update strategy

If I say “do the same as before” or “run the usual plugin check,” this is what I mean.

**Preferences:**

* Prioritize stability of LSP, autocompletion, navigation, and AI coding tools
* List any known update risks or major config changes needed
* Flag breaking changes or deprecations before recommending an update
* Share news about new plugin features, best practices, or useful tweaks

**Note:**
For Mason-installed packages (LSPs, DAPs, linters, etc.), I may also upload a backup/zip of my Mason directory before big updates, since Mason doesn’t have a built-in lockfile or rollback.

Let me know if you need more info!
