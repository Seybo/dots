import assert from "node:assert/strict";
import test from "node:test";

import { PickerState } from "./picker-state.ts";

test("starts on the first item and keeps marks while navigating", () => {
	const state = new PickerState(3);

	assert.equal(state.selectedIndex, 0);
	state.toggleMark();
	state.move(1);
	state.toggleMark();
	state.move(1);

	assert.equal(state.selectedIndex, 2);
	assert.equal(state.isMarked(0), true);
	assert.equal(state.isMarked(1), true);
});

test("moves to the next item without wrapping", () => {
	const state = new PickerState(3);

	state.moveNext();
	assert.equal(state.selectedIndex, 1);
	state.moveNext();
	state.moveNext();
	assert.equal(state.selectedIndex, 2);
});

test("toggles the highlighted item between marked and unmarked", () => {
	const state = new PickerState(2);

	state.toggleMark();
	assert.equal(state.isMarked(0), true);
	state.toggleMark();
	assert.equal(state.isMarked(0), false);
});

test("returns marked items in response order", () => {
	const state = new PickerState(3);
	state.move(-1);
	state.toggleMark();
	state.move(1);
	state.toggleMark();

	assert.deepEqual(state.chosenItems(["first", "second", "third"]), ["first", "third"]);
});

test("falls back to the highlighted item when nothing is marked", () => {
	const state = new PickerState(3);
	state.move(1);

	assert.deepEqual(state.chosenItems(["first", "second", "third"]), ["second"]);
});
