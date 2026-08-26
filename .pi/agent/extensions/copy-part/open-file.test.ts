import assert from "node:assert/strict";
import test from "node:test";

import { buildNvimCommand, resolveFileReference, selectIdlePane } from "./open-file.ts";

test("resolves absolute, home-relative, and project-relative file references", () => {
	assert.deepEqual(resolveFileReference("/tmp/file.rb:12:4", "/project", "/Users/test"), {
		path: "/tmp/file.rb",
		line: 12,
		column: 4,
	});
	assert.deepEqual(resolveFileReference("~/.config/app.lua", "/project", "/Users/test"), {
		path: "/Users/test/.config/app.lua",
	});
	assert.deepEqual(resolveFileReference("src/app.ts:7", "/project", "/Users/test"), {
		path: "/project/src/app.ts",
		line: 7,
	});
});

test("builds a safely quoted Neovim command with an optional cursor position", () => {
	assert.equal(buildNvimCommand({ path: "/project/a file's.rb" }), "nvim -- '/project/a file'\\''s.rb'");
	assert.equal(
		buildNvimCommand({ path: "/project/app.rb", line: 12, column: 4 }),
		"nvim '+call cursor(12, 4)' -- '/project/app.rb'",
	);
});

test("selects the first idle shell pane other than the current pane", () => {
	const panes = [
		{ id: "%1", command: "pi" },
		{ id: "%2", command: "nvim" },
		{ id: "%3", command: "zsh" },
	];

	assert.equal(selectIdlePane(panes, "%1", "zsh"), "%3");
	assert.equal(selectIdlePane(panes, "%1", "fish"), undefined);
});
