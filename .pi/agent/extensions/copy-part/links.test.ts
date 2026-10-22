import assert from "node:assert/strict";
import test from "node:test";

import { extractLinks } from "./links.ts";

test("extracts Markdown, autolink, and bare HTTP URLs in response order", () => {
	const markdown = [
		"Read the [Pi docs](https://example.com/docs).",
		"Then visit <http://example.org/start>.",
		"Finally use https://example.net/search?q=copy&mode=links",
	].join("\n\n");

	assert.deepEqual(extractLinks(markdown), [
		"https://example.com/docs",
		"http://example.org/start",
		"https://example.net/search?q=copy&mode=links",
	]);
});

test("excludes closing bold markers and sentence punctuation from bare links", () => {
	assert.deepEqual(
		extractLinks("Open **https://hichee.com/admin/flipper**. Then https://example.org/help."),
		["https://hichee.com/admin/flipper", "https://example.org/help"],
	);
});

test("excludes inline-code delimiters from links", () => {
	assert.deepEqual(extractLinks("Use `https://example.com/docs`."), ["https://example.com/docs"]);
});

test("preserves punctuation inside explicitly delimited URL destinations", () => {
	assert.deepEqual(
		extractLinks("[Search](https://example.com/search?q=why?) and <https://example.org/file.>"),
		["https://example.com/search?q=why?", "https://example.org/file."],
	);
});

test("preserves repeated URL occurrences", () => {
	const markdown = "https://example.com then [again](https://example.com)";

	assert.deepEqual(extractLinks(markdown), ["https://example.com", "https://example.com"]);
});

test("ignores URLs inside backtick and tilde fenced code blocks", () => {
	const markdown = [
		"https://before.example",
		"```sh",
		"curl https://ignored.example/backtick",
		"```",
		"~~~text",
		"https://ignored.example/tilde",
		"~~~",
		"<https://after.example>",
	].join("\n");

	assert.deepEqual(extractLinks(markdown), ["https://before.example", "https://after.example"]);
});

test("ignores unsupported reference, relative, anchor, and email links", () => {
	const markdown = [
		"[reference][docs]",
		"[docs]: https://reference.example/docs",
		"[relative](/docs)",
		"[anchor](#section)",
		"[email](mailto:person@example.com)",
	].join("\n");

	assert.deepEqual(extractLinks(markdown), []);
});
