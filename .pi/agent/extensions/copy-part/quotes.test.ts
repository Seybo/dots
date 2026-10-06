import assert from "node:assert/strict";
import test from "node:test";

import { extractQuotes } from "./quotes.ts";

test("extracts quoted responses in response order and removes quote markers", () => {
	const markdown = [
		"Before.",
		"",
		"> Yes. `Quote#book_direct_deal?` exists and is tested.",
		"> We’ll use it as a separate benefit.",
		"",
		"Between.",
		"",
		"  > Second quoted response.",
	].join("\n");

	assert.deepEqual(extractQuotes(markdown), [
		"Yes. `Quote#book_direct_deal?` exists and is tested.\nWe’ll use it as a separate benefit.",
		"Second quoted response.",
	]);
});

test("preserves blank quoted lines inside one response", () => {
	const markdown = ["> First paragraph.", ">", "> Second paragraph."].join("\n");

	assert.deepEqual(extractQuotes(markdown), ["First paragraph.\n\nSecond paragraph."]);
});

test("ignores quote-like text inside fenced code blocks and empty quotes", () => {
	const markdown = [
		"```text",
		"> not a quoted response",
		"```",
		"",
		">",
		">   ",
	].join("\n");

	assert.deepEqual(extractQuotes(markdown), []);
});
