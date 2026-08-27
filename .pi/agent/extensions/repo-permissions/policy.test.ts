import assert from "node:assert/strict";
import { chmodSync, mkdtempSync, mkdirSync, realpathSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import test from "node:test";

import {
	decideToolCall,
	getSshDestination,
	matchRule,
	parseProtectedPaths,
	parseRuleList,
	splitShellCommand,
	type RepositoryState,
} from "./policy.ts";

function withRepository(run: (state: RepositoryState, outside: string) => void): void {
	const base = mkdtempSync(join(tmpdir(), "repo-permissions-"));
	const rootPath = join(base, "repo");
	const outsidePath = join(base, "outside");
	mkdirSync(rootPath);
	mkdirSync(outsidePath);
	const root = realpathSync(rootPath);
	const outside = realpathSync(outsidePath);
	writeFileSync(join(root, "tracked.txt"), "tracked\n");
	writeFileSync(join(root, ".env"), "secret\n");
	writeFileSync(join(outside, "outside.txt"), "outside\n");
	symlinkSync(outside, join(root, "escape"));
	symlinkSync(outside, join(root, "protected-link"));
	symlinkSync(".env", join(root, "protected-alias"));
	symlinkSync("loop", join(root, "loop"));

	try {
		run(
			{
				root,
				protectedPaths: new Set([join(root, ".env"), join(root, "protected-link")]),
			},
			outside,
		);
	} finally {
		rmSync(base, { recursive: true, force: true });
	}
}

const call = (
	mode: "repository" | "ask" | "unrestricted",
	toolName: string,
	input: Record<string, unknown>,
	cwd: string,
	repository?: RepositoryState,
	skillRules: string[] = [],
	sshDestinations: Set<string> = new Set(),
) => decideToolCall({ mode, toolName, input, cwd, repository, skillRules, sshDestinations });

test("repository mode allows in-repo reads and ordinary edits", () => {
	withRepository((repository) => {
		assert.equal(call("repository", "read", { path: "tracked.txt" }, repository.root, repository).kind, "allow");
		assert.equal(call("repository", "read", { path: ".env" }, repository.root, repository).kind, "allow");
		assert.equal(call("repository", "edit", { path: "tracked.txt" }, repository.root, repository).kind, "allow");
		assert.equal(call("repository", "write", { path: "new.log" }, repository.root, repository).kind, "allow");
		writeFileSync(join(repository.root, "new.log"), "generated\n");
		assert.equal(call("repository", "edit", { path: "new.log" }, repository.root, repository).kind, "allow");
	});
});

test("repository mode prompts for baseline protected mutations", () => {
	withRepository((repository) => {
		const edit = call("repository", "edit", { path: ".env" }, repository.root, repository);
		const write = call("repository", "write", { path: join(repository.root, ".env") }, repository.root, repository);

		assert.equal(edit.kind, "ask");
		assert.match(edit.reason, /protected/i);
		assert.equal(write.kind, "ask");
		assert.equal(
			call("repository", "edit", { path: "protected-alias" }, repository.root, repository).kind,
			"ask",
		);
	});
});

test("repository mode prompts when paths escape through traversal or symlinks", () => {
	withRepository((repository, outside) => {
		assert.equal(
			call("repository", "read", { path: join(outside, "outside.txt") }, repository.root, repository).kind,
			"ask",
		);
		assert.equal(
			call("repository", "write", { path: "../outside/new.txt" }, repository.root, repository).kind,
			"ask",
		);
		assert.equal(
			call("repository", "read", { path: "escape/outside.txt" }, repository.root, repository).kind,
			"ask",
		);
		assert.equal(
			call("repository", "write", { path: "escape/new.txt" }, repository.root, repository).kind,
			"ask",
		);
		assert.equal(
			call("repository", "read", { path: "~/.ssh/config" }, repository.root, repository).kind,
			"ask",
		);
		assert.equal(call("repository", "read", { path: "loop" }, repository.root, repository).kind, "ask");
		assert.equal(call("repository", "read", { path: "tracked.txt\0tail" }, repository.root, repository).kind, "ask");
		assert.equal(call("repository", "read", { path: 123 }, repository.root, repository).kind, "ask");
		assert.equal(call("repository", "read", { path: "@tracked.txt" }, repository.root, repository).kind, "allow");
	});
});

test("Pi clipboard screenshots are readable outside the repository", () => {
	withRepository((repository, outside) => {
		const screenshot = join(outside, "pi-clipboard-23ad9380-9712-47c5-9b53-9ef475e99db1.png");
		const arbitraryImage = join(outside, "screenshot.png");
		const escapedScreenshot = join(outside, "pi-clipboard-11111111-2222-4333-8444-555555555555.png");
		writeFileSync(screenshot, "image\n");
		writeFileSync(arbitraryImage, "image\n");
		symlinkSync(process.execPath, escapedScreenshot);

		assert.equal(call("repository", "read", { path: screenshot }, repository.root, repository).kind, "allow");
		assert.equal(call("ask", "read", { path: screenshot }, repository.root, repository).kind, "allow");
		assert.equal(call("ask", "read", { path: arbitraryImage }, repository.root, repository).kind, "ask");
		assert.equal(call("ask", "edit", { path: screenshot }, repository.root, repository).kind, "ask");
		assert.equal(call("ask", "write", { path: screenshot }, repository.root, repository).kind, "ask");
		assert.equal(call("ask", "read", { path: escapedScreenshot }, repository.root, repository).kind, "ask");
	});
});

test("unreadable path parents fail closed when the filesystem enforces permissions", (context) => {
	withRepository((repository) => {
		const blockedDirectory = join(repository.root, "blocked");
		const blockedPath = join(blockedDirectory, "file.txt");
		mkdirSync(blockedDirectory);
		writeFileSync(blockedPath, "blocked\n");
		chmodSync(blockedDirectory, 0o000);

		try {
			try {
				realpathSync(blockedPath);
				context.skip("current user can bypass directory permissions");
				return;
			} catch {
				assert.equal(call("repository", "read", { path: blockedPath }, repository.root, repository).kind, "ask");
			}
		} finally {
			chmodSync(blockedDirectory, 0o700);
		}
	});
});

test("repository mode protects Git metadata mutations", () => {
	withRepository((repository) => {
		assert.equal(call("repository", "read", { path: ".git/config" }, repository.root, repository).kind, "allow");
		assert.equal(call("repository", "edit", { path: ".git/config" }, repository.root, repository).kind, "ask");
		assert.equal(
			call("repository", "write", { path: ".git/hooks/pre-commit" }, repository.root, repository).kind,
			"ask",
		);
		assert.equal(
			call("repository", "write", { path: "nested/.git" }, repository.root, repository).kind,
			"ask",
		);
		assert.equal(
			call("repository", "write", { path: ".GIT/hooks/pre-commit" }, repository.root, repository).kind,
			"ask",
		);
		assert.equal(call("repository", "write", { path: ".gitignore" }, repository.root, repository).kind, "allow");
		assert.equal(
			call("ask", "edit", { path: ".git/config" }, repository.root, repository, ["edit(*)"]).kind,
			"ask",
		);
	});
});

test("ask and unrestricted modes have one obvious behavior", () => {
	withRepository((repository) => {
		assert.equal(call("ask", "edit", { path: "tracked.txt" }, repository.root, repository).kind, "ask");
		assert.equal(
			call("unrestricted", "edit", { path: ".env" }, repository.root, repository).kind,
			"allow",
		);
		assert.equal(
			call("unrestricted", "bash", { command: "rm -rf /" }, repository.root, repository).kind,
			"allow",
		);
	});
});

test("session SSH grants allow one exact destination without relaxing local commands", () => {
	withRepository((repository) => {
		const destination = "dev@192.0.2.10";
		const grants = new Set([destination]);

		for (const mode of ["repository", "ask"] as const) {
			assert.equal(
				call(
					mode,
					"bash",
					{ command: `ssh ${destination} 'sudo touch /tmp/remote'` },
					repository.root,
					repository,
					[],
					grants,
				).kind,
				"allow",
			);
		}
		assert.equal(
			call(
				"repository",
				"bash",
				{ command: `ssh ${destination} true && ssh ${destination} 'rm /tmp/remote'` },
				repository.root,
				repository,
				[],
				grants,
			).kind,
			"allow",
		);
		for (const command of [
			"ssh other@192.0.2.10 true",
			`ssh ${destination} true && rm tracked.txt`,
			`ssh -J jump.example ${destination} true`,
			`ssh ${destination} "echo $HOME"`,
		]) {
			assert.equal(
				call("repository", "bash", { command }, repository.root, repository, [], grants).kind,
				"ask",
				command,
			);
		}

		assert.equal(getSshDestination(`ssh ${destination} 'sudo reboot'`), destination);
		assert.equal(getSshDestination(`ssh ${destination} true && ssh ${destination} false`), destination);
		assert.equal(getSshDestination(`ssh ${destination} true && rm tracked.txt`), undefined);
		assert.equal(getSshDestination(`ssh -J jump.example ${destination} true`), undefined);
	});
});

test("trusted skill rules allow exact tools but do not bypass protected direct edits", () => {
	withRepository((repository) => {
		const rules = ["bash(~/.dots/bin/helper *)", "read(/tmp/docs/*)", "edit(*)"];

		assert.equal(
			call("ask", "bash", { command: "~/.dots/bin/helper run" }, repository.root, repository, rules).kind,
			"allow",
		);
		assert.equal(
			call("repository", "read", { path: "/tmp/docs/file.md" }, repository.root, repository, rules).kind,
			"allow",
		);
		assert.equal(
			call("repository", "edit", { path: ".env" }, repository.root, repository, rules).kind,
			"ask",
		);
		assert.equal(
			call("repository", "edit", { path: "protected-link" }, repository.root, repository, rules).kind,
			"ask",
		);
		assert.equal(
			call(
				"ask",
				"bash",
				{ command: "~/.dots/bin/helper $(rm tracked.txt)" },
				repository.root,
				repository,
				rules,
			).kind,
			"ask",
		);
		assert.equal(
			call(
				"ask",
				"bash",
				{ command: "~/.dots/bin/helper run > result.txt" },
				repository.root,
				repository,
				rules,
			).kind,
			"ask",
		);
	});
});

test("read-only shell commands and chains are allowed only for in-repo paths", () => {
	withRepository((repository, outside) => {
		mkdirSync(join(repository.root, "src"));

		assert.equal(call("repository", "bash", { command: "pwd" }, repository.root, repository).kind, "allow");
		assert.equal(
			call("repository", "bash", { command: "rg TODO src | head -20" }, repository.root, repository).kind,
			"allow",
		);
		assert.equal(
			call("repository", "bash", { command: `rg TODO ${outside}` }, repository.root, repository).kind,
			"ask",
		);
		assert.equal(
			call("repository", "bash", { command: "rg TODO escape" }, repository.root, repository).kind,
			"ask",
		);
		assert.equal(
			call("repository", "bash", { command: "head *" }, repository.root, repository).kind,
			"ask",
		);
		assert.equal(
			call("repository", "bash", { command: "rg '*.ts' ." }, repository.root, repository).kind,
			"allow",
		);
		for (const command of ["rg -L TODO .", "rg --follow TODO .", "grep -R TODO .", "ls -LR ."]) {
			assert.equal(call("repository", "bash", { command }, repository.root, repository).kind, "ask", command);
		}
		for (const command of ["pwd && rg TODO .", "pwd || git status", "pwd; git status"]) {
			assert.equal(call("repository", "bash", { command }, repository.root, repository).kind, "allow", command);
		}
		assert.equal(
			call("repository", "bash", { command: "pwd || rm tracked.txt" }, repository.root, repository).kind,
			"ask",
		);
	});
});

test("read-only git inspection is allowed and mutating or risky shapes prompt", () => {
	withRepository((repository, outside) => {
		mkdirSync(join(repository.root, "nested"));
		assert.equal(
			call("repository", "bash", { command: "git status" }, repository.root, repository).kind,
			"allow",
		);
		assert.equal(
			call("repository", "bash", { command: "git branch --show-current" }, repository.root, repository).kind,
			"allow",
		);
		assert.equal(
			call("repository", "bash", { command: `git -C ${repository.root} diff` }, repository.root, repository).kind,
			"allow",
		);
		assert.equal(
			call("repository", "bash", { command: `git -C ${outside} status` }, repository.root, repository).kind,
			"ask",
		);
		assert.equal(
			call("repository", "bash", { command: "git checkout feature" }, repository.root, repository).kind,
			"ask",
		);
		assert.equal(
			call("repository", "bash", { command: "git branch -r -d origin/old" }, repository.root, repository).kind,
			"ask",
		);
		assert.equal(
			call(
				"repository",
				"bash",
				{ command: "git -C .. -C ../outside status" },
				join(repository.root, "nested"),
				repository,
			).kind,
			"ask",
		);
		assert.equal(
			call(
				"repository",
				"bash",
				{ command: "git -C nested -C .. status" },
				repository.root,
				repository,
			).kind,
			"allow",
		);
		assert.equal(
			call("repository", "bash", { command: "git diff --output=diff.txt" }, repository.root, repository).kind,
			"ask",
		);
		assert.equal(
			call(
				"repository",
				"bash",
				{ command: "git grep --open-files-in-pager=vim TODO" },
				repository.root,
				repository,
			).kind,
			"ask",
		);
	});
});

test("unsafe shell syntax, risky flags, and unknown programs prompt", () => {
	withRepository((repository) => {
		for (const command of [
			"rg TODO > result.txt",
			"rg $(cat query) .",
			"rg TODO `pwd`",
			"head {../outside/file,tracked.txt}",
			"rg --pre formatter TODO .",
			"rg --hostname-bin=./script TODO .",
			"sort -o sorted.txt input.txt",
			"sort -osorted.txt input.txt",
			"grep -f/etc/passwd tracked.txt",
			"find . -type f",
			"bundle exec rspec",
			"git status\nrm file",
		]) {
			assert.equal(
				call("repository", "bash", { command }, repository.root, repository).kind,
				"ask",
				command,
			);
		}
	});
});

test("clear path-aware alternatives are suggested", () => {
	withRepository((repository) => {
		const read = call("repository", "bash", { command: "cat tracked.txt" }, repository.root, repository);
		const edit = call("repository", "bash", { command: "sed -i s/a/b/ tracked.txt" }, repository.root, repository);
		const write = call("repository", "bash", { command: "printf hello > new.txt" }, repository.root, repository);

		assert.deepEqual(read, { kind: "suggest", tool: "read", reason: "Use read for file content." });
		assert.equal(edit.kind, "suggest");
		assert.equal(edit.tool, "edit");
		assert.equal(write.kind, "suggest");
		assert.equal(write.tool, "write");
	});
});

test("skill rules and command splitting remain anchored", () => {
	assert.deepEqual(parseRuleList("read grep bash(tool *)"), ["read", "grep", "bash(tool *)"]);
	assert.deepEqual(parseRuleList(["read", "bash(tool *)"]), ["read", "bash(tool *)"]);
	assert.equal(matchRule("bash(tool *)", "bash", "tool run"), true);
	assert.equal(matchRule("bash(tool *)", "bash", "other tool run"), false);
	assert.deepEqual(splitShellCommand("tool 'a|b' && head -1"), ["tool 'a|b'", "head -1"]);

	withRepository((repository) => {
		const rules = ["bash(tool *)"];
		assert.equal(
			call("ask", "bash", { command: "tool run && rm file" }, repository.root, repository, rules).kind,
			"ask",
		);
		assert.equal(
			call("ask", "bash", { command: "tool run\nrm file" }, repository.root, repository, rules).kind,
			"ask",
		);
	});
});

test("protected snapshots are rooted and NUL-safe", () => {
	const root = resolve("/tmp/example-repo");
	assert.deepEqual(
		parseProtectedPaths(root, ".env\0nested/local.json\0"),
		new Set([join(root, ".env"), join(root, "nested/local.json")]),
	);
});
