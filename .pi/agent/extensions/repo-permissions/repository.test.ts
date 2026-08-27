import assert from "node:assert/strict";
import { execFileSync, spawnSync } from "node:child_process";
import { mkdtempSync, mkdirSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";

import { decideToolCall } from "./policy.ts";
import { discoverRepository, type GitExec } from "./repository.ts";

const result = (code: number, stdout = "") => ({ code, stdout, stderr: "" });

test("repository discovery fails closed when Git root discovery fails", async () => {
	const missing = await discoverRepository("/tmp", async () => result(128));
	assert.deepEqual(missing, { hasGitRoot: false });

	const failed = await discoverRepository("/tmp", async () => {
		throw new Error("git unavailable");
	});
	assert.equal(failed.hasGitRoot, false);
	assert.match(failed.warning ?? "", /discovery failed/i);
});

test("repository discovery fails closed when the reported root cannot be resolved", async () => {
	const discovered = await discoverRepository("/tmp", async () => result(0, "/missing/repository/root\n"));
	assert.equal(discovered.hasGitRoot, false);
	assert.match(discovered.warning ?? "", /could not be resolved/i);
});

test("repository discovery fails closed when the protected snapshot fails", async () => {
	let callCount = 0;
	const discovered = await discoverRepository(process.cwd(), async () => {
		callCount++;
		return callCount === 1 ? result(0, `${process.cwd()}\n`) : result(1);
	});

	assert.equal(discovered.hasGitRoot, true);
	assert.equal(discovered.repository, undefined);
	assert.match(discovered.warning ?? "", /snapshot failed/i);
});

test("real Git snapshots include standard excludes but not files created later", async () => {
	const base = mkdtempSync(join(tmpdir(), "repo-discovery-"));
	const root = join(base, "repo");
	mkdirSync(root);

	try {
		execFileSync("git", ["init", "-q", root]);
		writeFileSync(join(root, ".gitignore"), ".env\n*.log\n");
		writeFileSync(join(root, ".env"), "secret\n");
		writeFileSync(join(root, "local.txt"), "local\n");
		writeFileSync(join(root, "global.tmp"), "global\n");
		writeFileSync(join(root, ".git", "info", "exclude"), "local.txt\n");
		const globalIgnore = join(base, "global-ignore");
		writeFileSync(globalIgnore, "global.tmp\n");
		execFileSync("git", ["-C", root, "config", "core.excludesFile", globalIgnore]);

		const discovered = await discoverRepository(root, gitExec);
		assert.equal(discovered.hasGitRoot, true);
		assert.ok(discovered.repository);
		assert.deepEqual(
			[...discovered.repository.protectedPaths].map((path) => path.slice(discovered.repository!.root.length + 1)).sort(),
			[".env", "global.tmp", "local.txt"],
		);

		writeFileSync(join(root, "generated.log"), "generated\n");
		assert.equal(
			decideToolCall({
				mode: "repository",
				toolName: "edit",
				input: { path: "generated.log" },
				cwd: root,
				repository: discovered.repository,
				skillRules: [],
			}).kind,
			"allow",
		);
	} finally {
		rmSync(base, { recursive: true, force: true });
	}
});

const gitExec: GitExec = async (command, args, options) => {
	const child = spawnSync(command, args, {
		cwd: options?.cwd,
		encoding: "utf8",
	});
	return result(child.status ?? 1, child.stdout ?? "");
};
