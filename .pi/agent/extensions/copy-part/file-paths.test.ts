import assert from "node:assert/strict";
import test from "node:test";

import { extractFilePaths } from "./file-paths.ts";

test("extracts supported file path forms in response order", () => {
	const markdown = [
		"Open [the config](./config/settings.json).",
		"Inspect /Users/inseybo/project/app/main.ts:42:7 next.",
		"Compare ../docs/guide.md with src/components/button.ts:18.",
		"Read /README.md at the filesystem root.",
	].join("\n");

	assert.deepEqual(extractFilePaths(markdown), [
		"./config/settings.json",
		"/Users/inseybo/project/app/main.ts:42:7",
		"../docs/guide.md",
		"src/components/button.ts:18",
		"/README.md",
	]);
});

test("strips Markdown and inline-code wrappers plus sentence punctuation", () => {
	const markdown = [
		"Update `.pi/agent/extensions/copy-part/index.ts`.",
		"See [the helper](lib/copy/file-paths.ts:9).",
	].join("\n");

	assert.deepEqual(extractFilePaths(markdown), [
		".pi/agent/extensions/copy-part/index.ts",
		"lib/copy/file-paths.ts:9",
	]);
});

test("preserves repeated path occurrences", () => {
	const markdown = "src/app/main.ts then [the same file](src/app/main.ts)";

	assert.deepEqual(extractFilePaths(markdown), ["src/app/main.ts", "src/app/main.ts"]);
});

test("ignores paths inside backtick and tilde fenced code blocks", () => {
	const markdown = [
		"src/before.ts",
		"```sh",
		"node scripts/ignored.ts",
		"```",
		"~~~text",
		"lib/also-ignored.rb",
		"~~~",
		"src/after.ts",
	].join("\n");

	assert.deepEqual(extractFilePaths(markdown), ["src/before.ts", "src/after.ts"]);
});

test("ignores web URLs, slash commands, standalone filenames, and slash-like prose", () => {
	const markdown = [
		"Visit https://example.com/docs/guide.md.",
		"Run /cp after /reload.",
		"README.md is standalone.",
		"Choose and/or values with a 1/2 ratio.",
	].join("\n");

	assert.deepEqual(extractFilePaths(markdown), []);
});
