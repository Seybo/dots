import assert from "node:assert/strict";
import { execFileSync, spawnSync } from "node:child_process";
import {
	mkdtempSync,
	mkdirSync,
	realpathSync,
	rmSync,
	symlinkSync,
	unlinkSync,
	writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join, relative } from "node:path";
import test from "node:test";

import { decideToolCall } from "./policy.ts";
import {
	discoverRepository,
	discoverRepositoryContaining,
	discoverTaskRepository,
	type GitExec,
} from "./repository.ts";

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

test("repository discovery fails closed when the Git-ignored file snapshot fails", async () => {
	let callCount = 0;
	const discovered = await discoverRepository(process.cwd(), async () => {
		callCount++;
		return callCount === 1 ? result(0, `${process.cwd()}\n`) : result(1);
	});

	assert.equal(discovered.hasGitRoot, true);
	assert.equal(discovered.repository, undefined);
	assert.match(discovered.warning ?? "", /snapshot failed/i);
});

test("repository discovery resolves a repository containing a new target", async () => {
	const base = mkdtempSync(join(tmpdir(), "repo-containing-"));
	const root = join(base, "repo");
	mkdirSync(join(root, "nested"), { recursive: true });

	try {
		execFileSync("git", ["init", "-q", root]);
		const discovered = await discoverRepositoryContaining(join(root, "nested", "new.txt"), gitExec);
		assert.equal(discovered.repository?.root, realpathSync(root));
	} finally {
		rmSync(base, { recursive: true, force: true });
	}
});

test("registered ordinal workspaces discover their exact task repository", async () => {
	const base = mkdtempSync(join(tmpdir(), "task-repository-ordinal-"));
	const devRoot = join(base, "dev");
	const codeRoot = join(devRoot, "projects", "foo");
	const checkout = join(codeRoot, "1st");
	const taskRoot = join(codeRoot, "_tasks");
	const registryPath = join(base, "projects.yml");
	mkdirSync(checkout, { recursive: true });
	mkdirSync(taskRoot);

	try {
		execFileSync("git", ["init", "-q", checkout]);
		execFileSync("git", ["init", "-q", taskRoot]);
		writeFileSync(join(taskRoot, ".gitignore"), "private.md\n");
		writeFileSync(join(taskRoot, "private.md"), "private\n");
		writeFileSync(
			registryPath,
			"version: 2\nprojects:\n  foo:\n    checkout_layout: ordinal_workspaces\n    code_root: projects/foo\n",
		);

		const discovered = await discoverTaskRepository(realpathSync(checkout), gitExec, {
			registryPath,
			devRoot,
			stowDir: join(base, "dots"),
		});

		assert.equal(discovered.repository?.root, realpathSync(taskRoot));
		assert.deepEqual(
			[...discovered.repository!.startupIgnoredPaths].map((path) =>
				relative(discovered.repository!.root, path),
			),
			["private.md"],
		);
	} finally {
		rmSync(base, { recursive: true, force: true });
	}
});

test("registered direct checkouts allow their missing prospective task repository", async () => {
	const base = mkdtempSync(join(tmpdir(), "task-repository-direct-"));
	const checkout = join(base, "dots");
	const registryPath = join(base, "projects.yml");
	mkdirSync(checkout);

	try {
		execFileSync("git", ["init", "-q", checkout]);
		writeFileSync(
			registryPath,
			"version: 2\nprojects:\n  env:\n    checkout_layout: direct\n    checkout_path: $STOW_DIR\n",
		);

		const discovered = await discoverTaskRepository(realpathSync(checkout), gitExec, {
			registryPath,
			devRoot: join(base, "dev"),
			stowDir: checkout,
		});

		assert.equal(discovered.repository?.root, join(realpathSync(checkout), "_tasks"));
		assert.deepEqual([...discovered.repository!.startupIgnoredPaths], []);
	} finally {
		rmSync(base, { recursive: true, force: true });
	}
});

test("task repository discovery rejects unregistered and symlinked task roots", async () => {
	const base = mkdtempSync(join(tmpdir(), "task-repository-rejected-"));
	const devRoot = join(base, "dev");
	const codeRoot = join(devRoot, "projects", "foo");
	const checkout = join(codeRoot, "1st");
	const malformedCheckout = join(codeRoot, "11st");
	const outside = join(base, "outside-tasks");
	const taskRoot = join(codeRoot, "_tasks");
	const emptyRegistry = join(base, "empty.yml");
	const registryPath = join(base, "projects.yml");
	mkdirSync(checkout, { recursive: true });
	mkdirSync(malformedCheckout);
	mkdirSync(outside);

	try {
		execFileSync("git", ["init", "-q", checkout]);
		execFileSync("git", ["init", "-q", malformedCheckout]);
		execFileSync("git", ["init", "-q", outside]);
		symlinkSync(outside, taskRoot);
		writeFileSync(emptyRegistry, "version: 2\nprojects: {}\n");
		writeFileSync(
			registryPath,
			"version: 2\nprojects:\n  foo:\n    checkout_layout: ordinal_workspaces\n    code_root: projects/foo\n",
		);

		const unregistered = await discoverTaskRepository(realpathSync(checkout), gitExec, {
			registryPath: emptyRegistry,
			devRoot,
			stowDir: join(base, "dots"),
		});
		assert.equal(unregistered.repository, undefined);

		const malformed = await discoverTaskRepository(realpathSync(malformedCheckout), gitExec, {
			registryPath,
			devRoot,
			stowDir: join(base, "dots"),
		});
		assert.equal(malformed.repository, undefined);
		assert.equal(malformed.warning, undefined);

		const symlinked = await discoverTaskRepository(realpathSync(checkout), gitExec, {
			registryPath,
			devRoot,
			stowDir: join(base, "dots"),
		});
		assert.equal(symlinked.repository, undefined);
		assert.match(symlinked.warning ?? "", /symbolic link/i);

		unlinkSync(taskRoot);
		mkdirSync(taskRoot);
		const nonGit = await discoverTaskRepository(realpathSync(checkout), gitExec, {
			registryPath,
			devRoot,
			stowDir: join(base, "dots"),
		});
		assert.equal(nonGit.repository, undefined);
		assert.match(nonGit.warning ?? "", /not a Git repository/i);
	} finally {
		rmSync(base, { recursive: true, force: true });
	}
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
			[...discovered.repository.startupIgnoredPaths]
				.map((path) => path.slice(discovered.repository!.root.length + 1))
				.sort(),
			[".env", "global.tmp", "local.txt"],
		);

		writeFileSync(join(root, "generated.log"), "generated\n");
		assert.equal(
			decideToolCall({
				mode: "repository",
				toolName: "edit",
				input: { path: "generated.log" },
				cwd: root,
				repositories: discovered.repository ? [discovered.repository] : [],
				skillRules: [],
				sshDestinations: new Set(),
				httpOrigins: new Set(),
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
