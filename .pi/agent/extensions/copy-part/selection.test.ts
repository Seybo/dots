import assert from "node:assert/strict";
import test from "node:test";

import { parseCopyArgs, resolveSelection } from "./selection.ts";

test("parses a mode with no selector for picker routing", () => {
	assert.deepEqual(parseCopyArgs(" c "), { mode: "c" });
});

test("parses link mode with l as an unambiguous last-item selector", () => {
	assert.deepEqual(parseCopyArgs("l l"), { mode: "l", selector: "l" });
});

test("rejects missing and extra command arguments", () => {
	assert.equal(parseCopyArgs(""), undefined);
	assert.equal(parseCopyArgs("c 1 extra"), undefined);
});

test("routes a missing selector to the picker", () => {
	assert.deepEqual(resolveSelection(["first", "second"], undefined), { kind: "picker" });
});

test("resolves one-based numeric selectors", () => {
	const items = ["first", "second", "third"];

	assert.deepEqual(resolveSelection(items, "1"), { kind: "item", item: "first" });
	assert.deepEqual(resolveSelection(items, "3"), { kind: "item", item: "third" });
});

test("resolves l to the last item", () => {
	assert.deepEqual(resolveSelection(["first", "second"], "l"), {
		kind: "item",
		item: "second",
	});
});

test("rejects malformed, unsupported, and out-of-range selectors", () => {
	for (const selector of ["0", "-1", "1.5", "last", "all", "3"]) {
		assert.deepEqual(resolveSelection(["first", "second"], selector), { kind: "invalid" });
	}
});
