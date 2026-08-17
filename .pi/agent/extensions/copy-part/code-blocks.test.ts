import assert from "node:assert/strict";
import test from "node:test";

import { extractCodeBlocks } from "./code-blocks.ts";

test("extracts backtick and tilde fence bodies in response order", () => {
	const markdown = [
		"Before.",
		"",
		"```ts",
		"const value = 1;",
		"  console.log(value);",
		"```",
		"",
		"~~~~ ruby metadata",
		"puts :ok",
		"~~~~",
		"",
		"After.",
	].join("\n");

	assert.deepEqual(extractCodeBlocks(markdown), [
		"const value = 1;\n  console.log(value);",
		"puts :ok",
	]);
});

test("preserves body indentation, blank lines, and trailing spaces", () => {
	const markdown = ["```text", "  first", "", "second  ", "```"].join("\n");

	assert.deepEqual(extractCodeBlocks(markdown), ["  first\n\nsecond  "]);
});

test("ignores prose, inline code, and empty fenced blocks", () => {
	const markdown = [
		"Prose with `inline code`.",
		"",
		"```",
		"```",
		"",
		"~~~text",
		"   ",
		"~~~",
	].join("\n");

	assert.deepEqual(extractCodeBlocks(markdown), []);
});

test("requires a closing fence at least as long as its opening fence", () => {
	const markdown = ["````md", "```", "const value = true;", "````"].join("\n");

	assert.deepEqual(extractCodeBlocks(markdown), ["```\nconst value = true;"]);
});
