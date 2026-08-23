import assert from "node:assert/strict";
import test from "node:test";

import { extractCodeParts } from "./code-blocks.ts";

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

	assert.deepEqual(extractCodeParts(markdown), [
		"const value = 1;\n  console.log(value);",
		"puts :ok",
	]);
});

test("keeps inline code and fenced bodies in response order", () => {
	const markdown = [
		"Run `/skill:autoimplement 39589` first.",
		"```sh",
		"bin/check",
		"```",
		"Then use `pbcopy`.",
	].join("\n");

	assert.deepEqual(extractCodeParts(markdown), [
		"/skill:autoimplement 39589",
		"bin/check",
		"pbcopy",
	]);
});

test("preserves body indentation, blank lines, and trailing spaces", () => {
	const markdown = ["```text", "  first", "", "second  ", "```"].join("\n");

	assert.deepEqual(extractCodeParts(markdown), ["  first\n\nsecond  "]);
});

test("extracts inline code while ignoring prose and empty fenced blocks", () => {
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

	assert.deepEqual(extractCodeParts(markdown), ["inline code"]);
});

test("requires a closing fence at least as long as its opening fence", () => {
	const markdown = ["````md", "```", "const value = true;", "````"].join("\n");

	assert.deepEqual(extractCodeParts(markdown), ["```\nconst value = true;"]);
});
