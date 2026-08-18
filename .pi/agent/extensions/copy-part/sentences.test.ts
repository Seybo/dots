import assert from "node:assert/strict";
import test from "node:test";

import { extractSentences } from "./sentences.ts";

test("preserves raw Markdown and response order", () => {
	assert.deepEqual(extractSentences("First **sentence**. Second `sentence`."), [
		"First **sentence**.",
		"Second `sentence`.",
	]);
});

test("keeps headings and list prose while dropping blank segments", () => {
	assert.deepEqual(extractSentences("# Heading\n\n- First sentence. Second sentence."), [
		"# Heading",
		"- First sentence.",
		"Second sentence.",
	]);
});

test("keeps numbered-line prefixes with their sentence", () => {
	const markdown = [
		"Understood. For each response, assess:",
		"",
		"1. What follows the current rules.",
		"2. What does not.",
	].join("\n");

	assert.deepEqual(extractSentences(markdown), [
		"Understood.",
		"For each response, assess:",
		"1. What follows the current rules.",
		"2. What does not.",
	]);
});

test("returns no candidates for blank content", () => {
	assert.deepEqual(extractSentences(" \n\n\t"), []);
});

test("excludes fenced code blocks", () => {
	const markdown = [
		"Before the code.",
		"",
		"```ts",
		'const message = "Do not include this sentence.";',
		"```",
		"",
		"After the code.",
		"",
		"~~~text",
		"Neither should this sentence appear.",
		"~~~",
	].join("\n");

	assert.deepEqual(extractSentences(markdown), ["Before the code.", "After the code."]);
});
