import assert from "node:assert/strict";
import test from "node:test";

import { formatSentenceList } from "./sentence-list.ts";

test("formats selected sentences as a numbered list in input order", () => {
	assert.equal(
		formatSentenceList(["Third response sentence.", "First response sentence."]),
		"1. Third response sentence.\n2. First response sentence.",
	);
});

test("replaces existing numbered prefixes without changing other content", () => {
	assert.equal(
		formatSentenceList(["3. Render the follow-up.", "12. Add **the preview**."]),
		"1. Render the follow-up.\n2. Add **the preview**.",
	);
});
