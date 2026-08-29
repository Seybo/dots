import assert from "node:assert/strict";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";

import { registerRepoPermissions } from "./extension.ts";

type Handler = (event: Record<string, unknown>, context: ReturnType<typeof createContext>) => Promise<unknown>;

type ExecResult = { code: number; stdout: string; stderr: string };

function createHarness(
	results: ExecResult[],
	skillCommands: Record<string, unknown>[] = [],
	parseFrontmatter: (content: string) => Record<string, unknown> = () => ({}),
) {
	const handlers = new Map<string, Handler>();
	const commands = new Map<string, { handler: Handler }>();
	const pi = {
		exec: async () => results.shift() ?? { code: 1, stdout: "", stderr: "" },
		on: (name: string, handler: Handler) => handlers.set(name, handler),
		registerCommand: (name: string, command: { handler: Handler }) => commands.set(name, command),
		getCommands: () => skillCommands,
	};
	registerRepoPermissions(pi as never, parseFrontmatter);
	return { handlers, commands };
}

function createContext(cwd: string, hasUI = true) {
	const statuses: Array<string | undefined> = [];
	const notifications: string[] = [];
	const selections: string[][] = [];
	const selectionTitles: string[] = [];
	const answers: Array<string | undefined> = [];
	let isAborted = false;

	return {
		cwd,
		hasUI,
		statuses,
		notifications,
		selections,
		selectionTitles,
		answers,
		get isAborted() {
			return isAborted;
		},
		abort: () => {
			isAborted = true;
		},
		ui: {
			theme: { fg: (_color: string, text: string) => text },
			setStatus: (_id: string, value: string | undefined) => statuses.push(value),
			notify: (message: string) => notifications.push(message),
			select: async (title: string, choices: string[]) => {
				selectionTitles.push(title);
				selections.push(choices);
				return answers.shift();
			},
		},
	};
}

const gitResult = (code: number, stdout = ""): ExecResult => ({ code, stdout, stderr: "" });

test("outside Git starts in Ask mode, omits Repository, and resets session choices", async () => {
	const harness = createHarness([gitResult(1), gitResult(1)]);
	const context = createContext("/tmp");

	await harness.handlers.get("session_start")!({}, context);
	assert.equal(context.statuses.at(-1), "permissions: ask");

	context.answers.push("Unrestricted");
	await harness.commands.get("permissions")!.handler({}, context);
	assert.deepEqual(context.selections.at(-1), ["Ask", "Unrestricted"]);
	assert.equal(context.statuses.at(-1), "permissions: unrestricted");

	await harness.handlers.get("session_start")!({}, context);
	assert.equal(context.statuses.at(-1), "permissions: ask");
});

test("snapshot failure stays in Ask mode and reports the failure", async () => {
	const root = process.cwd();
	const harness = createHarness([gitResult(0, `${root}\n`), gitResult(1)]);
	const context = createContext(root);

	await harness.handlers.get("session_start")!({}, context);
	assert.equal(context.statuses.at(-1), "permissions: ask");
	assert.match(context.notifications.at(-1) ?? "", /snapshot failed/i);
	await harness.commands.get("permissions")!.handler({}, context);
	assert.deepEqual(context.selections.at(-1), ["Repository", "Ask", "Unrestricted"]);
});

test("Repository selection refreshes startup ignored paths", async () => {
	const root = process.cwd();
	const harness = createHarness([
		gitResult(0, `${root}\n`),
		gitResult(0, ".env\0"),
		gitResult(0, `${root}\n`),
		gitResult(0, "later.log\0"),
	]);
	const context = createContext(root, false);

	await harness.handlers.get("session_start")!({}, context);
	assert.equal(context.statuses.at(-1), "permissions: repo");
	const first = await harness.handlers.get("tool_call")!(
		{ toolName: "edit", input: { path: ".env" } },
		context,
	);
	assert.deepEqual(first, {
		block: true,
		reason:
			"Blocked because approval is unavailable: The target of .env was untracked and Git-ignored when Repository mode started.",
	});

	context.answers.push("Repository");
	await harness.commands.get("permissions")!.handler({}, context);
	assert.deepEqual(context.selections.at(-1), ["Repository", "Unattended", "Ask", "Unrestricted"]);
	const refreshed = await harness.handlers.get("tool_call")!(
		{ toolName: "edit", input: { path: "later.log" } },
		context,
	);
	assert.equal((refreshed as { block?: boolean }).block, true);
});

test("Unattended mode blocks approval-required work without prompting", async () => {
	const root = process.cwd();
	const harness = createHarness([
		gitResult(0, `${root}\n`),
		gitResult(0),
		gitResult(0, `${root}\n`),
		gitResult(0),
	]);
	const context = createContext(root);

	await harness.handlers.get("session_start")!({}, context);
	context.answers.push("Unattended");
	await harness.commands.get("permissions")!.handler({}, context);
	assert.equal(context.statuses.at(-1), "permissions: unattended");

	const selectionCount = context.selections.length;
	assert.deepEqual(
		await harness.handlers.get("tool_call")!(
			{ toolName: "bash", input: { command: "git push origin main" } },
			context,
		),
		{
			block: true,
			reason:
				"Blocked in Unattended mode: This Git operation requires approval. Continue with permitted work and report this blocked operation.",
		},
	);
	assert.equal(context.selections.length, selectionCount);
	assert.equal(
		await harness.handlers.get("tool_call")!({ toolName: "read", input: { path: "README.md" } }, context),
		undefined,
	);

	await harness.handlers.get("session_start")!({}, context);
	assert.equal(context.statuses.at(-1), "permissions: repo");
});

test("standard scalar allowed-tools rules are loaded from trusted local skills", async () => {
	const directory = mkdtempSync(join(tmpdir(), "repo-permission-skill-"));
	const skillPath = join(directory, "SKILL.md");
	writeFileSync(skillPath, "---\nallowed-tools: read grep\n---\n");

	try {
		const harness = createHarness(
			[gitResult(1)],
			[
				{
					source: "skill",
					sourceInfo: { origin: "top-level", scope: "user", path: skillPath },
				},
			],
			() => ({ "allowed-tools": "read grep" }),
		);
		const context = createContext("/tmp", false);
		await harness.handlers.get("session_start")!({}, context);
		assert.equal(
			await harness.handlers.get("tool_call")!({ toolName: "read", input: { path: "/tmp/file" } }, context),
			undefined,
		);
		assert.equal(
			await harness.handlers.get("tool_call")!({ toolName: "grep", input: { path: "/tmp" } }, context),
			undefined,
		);
	} finally {
		rmSync(directory, { recursive: true, force: true });
	}
});

test("approval prompts truncate large Bash and custom-tool details", async () => {
	const harness = createHarness([gitResult(1)]);
	const context = createContext("/tmp");
	await harness.handlers.get("session_start")!({}, context);

	for (const event of [
		{ toolName: "bash", input: { command: `unknown ${"x".repeat(20_000)}` } },
		{ toolName: "custom", input: { payload: "x".repeat(20_000) } },
	]) {
		context.answers.push("Reject");
		await harness.handlers.get("tool_call")!(event, context);
		const title = context.selectionTitles.at(-1) ?? "";
		assert.ok(title.length < 1_500, `${event.toolName} title was ${title.length} characters`);
		assert.match(title, /truncated/i);
	}
});

test("SSH destination approval is scoped to the current session", async () => {
	const destination = "dev@192.0.2.10";
	const sshChoice = `Allow SSH access to ${destination} for this session`;
	const harness = createHarness([gitResult(1), gitResult(1)]);
	const context = createContext("/tmp");
	await harness.handlers.get("session_start")!({}, context);

	context.answers.push(sshChoice);
	assert.equal(
		await harness.handlers.get("tool_call")!(
			{
				toolName: "bash",
				input: { command: `scp /tmp/local ${destination}:/home/svin/remote && ssh ${destination} true` },
			},
			context,
		),
		undefined,
	);
	assert.deepEqual(context.selections.at(-1), [
		"Allow once",
		sshChoice,
		"Allow everything for this session",
		"Reject",
	]);
	assert.match(context.notifications.at(-1) ?? "", new RegExp(destination.replaceAll(".", "\\.")));

	const selectionCount = context.selections.length;
	for (const command of [
		`ssh ${destination} 'anything > /tmp/remote'`,
		`scp /tmp/local ${destination}:/home/svin/remote && ssh ${destination} true`,
		`scp "$STOW_DIR/local" ${destination}:/home/svin/remote && ssh ${destination} true`,
	]) {
		assert.equal(
			await harness.handlers.get("tool_call")!({ toolName: "bash", input: { command } }, context),
			undefined,
		);
	}
	assert.equal(context.selections.length, selectionCount);

	for (const command of ["ssh other@192.0.2.10 true", "rm local-file"]) {
		context.answers.push("Allow once");
		await harness.handlers.get("tool_call")!({ toolName: "bash", input: { command } }, context);
	}
	assert.equal(context.selections.length, selectionCount + 2);

	await harness.handlers.get("session_start")!({}, context);
	context.answers.push("Reject");
	const reset = await harness.handlers.get("tool_call")!(
		{ toolName: "bash", input: { command: `ssh ${destination} true` } },
		context,
	);
	assert.deepEqual(reset, { block: true, reason: "Rejected by user" });
});

test("noninteractive approval is blocked while interactive unrestricted approval is session-only", async () => {
	const harness = createHarness([gitResult(1), gitResult(1)]);
	const noninteractive = createContext("/tmp", false);
	await harness.handlers.get("session_start")!({}, noninteractive);
	const blocked = await harness.handlers.get("tool_call")!(
		{ toolName: "bash", input: { command: "rm file" } },
		noninteractive,
	);
	assert.equal((blocked as { block?: boolean }).block, true);

	const interactive = createContext("/tmp");
	await harness.handlers.get("session_start")!({}, interactive);
	interactive.answers.push("Allow everything for this session");
	assert.equal(
		await harness.handlers.get("tool_call")!(
			{ toolName: "bash", input: { command: "rm file" } },
			interactive,
		),
		undefined,
	);
	assert.equal(interactive.statuses.at(-1), "permissions: unrestricted");
	assert.equal(
		await harness.handlers.get("tool_call")!(
			{ toolName: "bash", input: { command: "rm another" } },
			interactive,
		),
		undefined,
	);
});
