import assert from "node:assert/strict";
import test from "node:test";
import extension from "./index.ts";

function setup(mode = "tui") {
	const handlers = new Map<string, (event: unknown, ctx: any) => void>();
	const statuses = new Map<string, string | undefined>([["permissions", "permissions: repo"]]);
	const writes: (string | undefined)[] = [];
	const styles: unknown[] = [];
	let name: string | undefined = "env-oma";
	let palette = "light";
	const ctx = {
		mode,
		sessionManager: { getSessionName: () => name },
		ui: {
			get theme() {
				return {
					colors: { warning: `${palette}-warning` },
					style(text: string, options: unknown) {
						styles.push(options);
						return `${palette}[${text}]`;
					},
				};
			},
			setStatus(key: string, value: string | undefined) {
				assert.equal(key, "session-name");
				statuses.set(key, value);
				writes.push(value);
			},
			setFooter() { assert.fail("must not replace the footer"); },
		},
	};
	extension({ on: (event: string, handler: any) => handlers.set(event, handler) } as any);
	return {
		statuses, writes, styles,
		emit: (event: string) => handlers.get(event)!({}, ctx),
		name: (value: string | undefined) => { name = value; },
		palette: (value: string) => { palette = value; },
	};
}

test("factory has no side effects; startup adds a padded badge without touching other statuses", (t) => {
	t.mock.timers.enable({ apis: ["setInterval"] });
	const state = setup();
	t.mock.timers.tick(2000);
	assert.deepEqual(state.writes, []);
	state.emit("session_start");
	assert.equal(state.statuses.get("session-name"), "light[ env-oma ]");
	assert.deepEqual(state.styles.at(-1), { fg: "text", bg: "selectedBg", bold: true });
	assert.equal(state.statuses.get("permissions"), "permissions: repo");
	state.emit("session_shutdown");
});

test("only the exact manager name uses the current warning background", (t) => {
	t.mock.timers.enable({ apis: ["setInterval"] });
	const state = setup();
	state.name("manager");
	state.emit("session_start");
	assert.equal(state.statuses.get("session-name"), "light[ manager ]");
	assert.deepEqual(state.styles.at(-1), { fg: { kind: "rgb", r: 255, g: 255, b: 255 }, bg: "light-warning", bold: true });
	state.palette("dark");
	t.mock.timers.tick(1000);
	assert.deepEqual(state.styles.at(-1), { fg: { kind: "rgb", r: 255, g: 255, b: 255 }, bg: "dark-warning", bold: true });
	for (const name of ["worker", "Manager", "manager-1"]) {
		state.name(name);
		state.emit("session_info_changed");
		assert.deepEqual(state.styles.at(-1), { fg: "text", bg: "selectedBg", bold: true });
	}
	state.emit("session_shutdown");
});

test("renaming a regular session to manager immediately changes its background", (t) => {
	t.mock.timers.enable({ apis: ["setInterval"] });
	const state = setup();
	state.emit("session_start");
	state.name("manager");
	state.emit("session_info_changed");
	assert.deepEqual(state.styles.at(-1), { fg: { kind: "rgb", r: 255, g: 255, b: 255 }, bg: "light-warning", bold: true });
	state.emit("session_shutdown");
});

test("unnamed sessions have no badge", (t) => {
	t.mock.timers.enable({ apis: ["setInterval"] });
	const state = setup();
	state.name(undefined);
	state.emit("session_start");
	assert.equal(state.statuses.get("session-name"), undefined);
	state.emit("session_shutdown");
});

test("rename and clear update immediately", (t) => {
	t.mock.timers.enable({ apis: ["setInterval"] });
	const state = setup();
	state.emit("session_start");
	state.name("new name");
	state.emit("session_info_changed");
	assert.equal(state.statuses.get("session-name"), "light[ new name ]");
	state.name(undefined);
	state.emit("session_info_changed");
	assert.equal(state.statuses.get("session-name"), undefined);
	state.emit("session_shutdown");
});

test("theme refresh uses current colors without redundant status writes", (t) => {
	t.mock.timers.enable({ apis: ["setInterval"] });
	const state = setup();
	state.emit("session_start");
	t.mock.timers.tick(3000);
	assert.equal(state.writes.length, 1);
	state.palette("dark");
	t.mock.timers.tick(1000);
	assert.equal(state.statuses.get("session-name"), "dark[ env-oma ]");
	assert.equal(state.writes.length, 2);
	state.emit("session_shutdown");
});

test("session switches reset the status and replace the old refresh timer", (t) => {
	t.mock.timers.enable({ apis: ["setInterval"] });
	const state = setup();
	state.emit("session_start");
	state.name("other session");
	state.emit("session_start");
	assert.equal(state.statuses.get("session-name"), "light[ other session ]");
	state.name(undefined);
	state.emit("session_start");
	assert.equal(state.statuses.get("session-name"), undefined);
	state.emit("session_shutdown");
	const writesCount = state.writes.length;
	state.palette("dark");
	t.mock.timers.tick(3000);
	assert.equal(state.writes.length, writesCount);
	assert.equal(state.statuses.get("session-name"), undefined);
});

test("shutdown is safe before startup and after shutdown", (t) => {
	t.mock.timers.enable({ apis: ["setInterval"] });
	const state = setup();
	state.emit("session_shutdown");
	state.emit("session_shutdown");
	t.mock.timers.tick(3000);
	assert.equal(state.statuses.get("session-name"), undefined);
});

for (const mode of ["rpc", "print", "json"]) {
	test(`${mode} mode does not create a badge or refresh timer`, (t) => {
		t.mock.timers.enable({ apis: ["setInterval"] });
		const state = setup(mode);
		state.emit("session_start");
		state.emit("session_info_changed");
		t.mock.timers.tick(3000);
		state.emit("session_shutdown");
		assert.deepEqual(state.writes, []);
	});
}
