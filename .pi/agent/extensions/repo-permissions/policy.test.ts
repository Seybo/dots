import assert from "node:assert/strict";
import { mkdtempSync, mkdirSync, realpathSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import test from "node:test";

import {
	decideToolCall,
	getSshDestination,
	matchRule,
	parseStartupIgnoredPaths,
	parseRuleList,
	splitShellCommand,
	type PermissionMode,
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
	symlinkSync(outside, join(root, "outside-link"));
	symlinkSync(".env", join(root, "ignored-alias"));
	symlinkSync("loop", join(root, "loop"));

	try {
		run({ root, startupIgnoredPaths: new Set([join(root, ".env")]) }, outside);
	} finally {
		rmSync(base, { recursive: true, force: true });
	}
}

const call = (
	mode: PermissionMode,
	toolName: string,
	input: Record<string, unknown>,
	cwd: string,
	repository?: RepositoryState,
	skillRules: string[] = [],
	sshDestinations: Set<string> = new Set(),
) => decideToolCall({ mode, toolName, input, cwd, repository, skillRules, sshDestinations });

test("repository mode allows ordinary tools inside and outside the repository", () => {
	withRepository((repository, outside) => {
		assert.equal(call("repository", "read", { path: "tracked.txt" }, repository.root, repository).kind, "allow");
		assert.equal(call("repository", "edit", { path: "tracked.txt" }, repository.root, repository).kind, "allow");
		assert.equal(call("repository", "write", { path: "new.txt" }, repository.root, repository).kind, "allow");
		assert.equal(
			call("repository", "read", { path: join(outside, "outside.txt") }, repository.root, repository).kind,
			"allow",
		);
		assert.equal(
			call("repository", "edit", { path: join(outside, "outside.txt") }, repository.root, repository).kind,
			"allow",
		);
		assert.equal(
			call("repository", "write", { path: "outside-link/new.txt" }, repository.root, repository).kind,
			"allow",
		);
		assert.equal(call("repository", "custom", { payload: "work" }, repository.root, repository).kind, "allow");
	});
});

test("repository mode allows literal in-repository rm targets", () => {
	withRepository((repository) => {
		for (const command of [
			"rm tracked.txt",
			"rm -rf subdir",
			"rm outside-link",
			"git rm tracked.txt",
		]) {
			assert.equal(call("repository", "bash", { command }, repository.root, repository).kind, "allow", command);
		}
	});
});

test("repository mode asks for rm targets that are outside, dynamic, or specially guarded", () => {
	withRepository((repository, outside) => {
		for (const command of [
			`rm ${outside}/outside.txt`,
			"rm ../outside/outside.txt",
			"rm outside-link/outside.txt",
			"rm -rf outside-link/",
			"rm -rf outside-link/.",
			"cd /tmp && rm outside.txt",
			"rm \"$TARGET\"",
			"rm *.txt",
			"rm .env",
			"rm .git/config",
			"rm -rf .",
		]) {
			assert.equal(call("repository", "bash", { command }, repository.root, repository).kind, "ask", command);
		}
	});
});

test("repository mode asks before changing startup-ignored files and Git metadata", () => {
	withRepository((repository) => {
		assert.equal(call("repository", "read", { path: ".env" }, repository.root, repository).kind, "allow");
		assert.equal(call("repository", "edit", { path: ".env" }, repository.root, repository).kind, "ask");
		assert.equal(call("repository", "write", { path: "ignored-alias" }, repository.root, repository).kind, "ask");
		assert.equal(call("repository", "read", { path: ".git/config" }, repository.root, repository).kind, "allow");
		assert.equal(call("repository", "edit", { path: ".git/config" }, repository.root, repository).kind, "ask");
		assert.equal(call("repository", "write", { path: "nested/.GIT/config" }, repository.root, repository).kind, "ask");
		assert.equal(call("repository", "write", { path: ".gitignore" }, repository.root, repository).kind, "allow");
	});
});

test("direct mutation checks fail closed for malformed paths", () => {
	withRepository((repository) => {
		assert.equal(call("repository", "edit", { path: "loop" }, repository.root, repository).kind, "ask");
		assert.equal(call("repository", "write", { path: "tracked.txt\0tail" }, repository.root, repository).kind, "ask");
		assert.equal(call("repository", "edit", { path: 123 }, repository.root, repository).kind, "ask");
	});
});

test("Pi clipboard screenshots are readable in every guarded mode", () => {
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
		assert.equal(call("ask", "read", { path: escapedScreenshot }, repository.root, repository).kind, "ask");
	});
});

test("Ask and Unrestricted modes keep simple defaults", () => {
	withRepository((repository) => {
		assert.equal(call("ask", "read", { path: "tracked.txt" }, repository.root, repository).kind, "ask");
		assert.equal(call("ask", "custom", {}, repository.root, repository).kind, "ask");
		assert.equal(call("unattended", "read", { path: "tracked.txt" }, repository.root, repository).kind, "allow");
		assert.equal(call("unattended", "bash", { command: "git push origin main" }, repository.root, repository).kind, "ask");
		assert.equal(call("unrestricted", "bash", { command: "sudo rm -rf /" }, repository.root, repository).kind, "allow");
		assert.equal(call("unrestricted", "edit", { path: ".env" }, repository.root, repository).kind, "allow");
	});
});

test("trusted skill rules do not bypass startup-ignored or guarded operations", () => {
	withRepository((repository) => {
		const rules = ["bash(~/.dots/bin/helper *)", "bash(git push *)", "read(/tmp/docs/*)", "edit(*)"];
		assert.equal(
			call("ask", "bash", { command: "~/.dots/bin/helper run" }, repository.root, repository, rules).kind,
			"allow",
		);
		assert.equal(call("ask", "read", { path: "/tmp/docs/file.md" }, repository.root, repository, rules).kind, "allow");
		assert.equal(call("ask", "bash", { command: "git push origin main" }, repository.root, repository, rules).kind, "ask");
		assert.equal(call("ask", "edit", { path: ".env" }, repository.root, repository, rules).kind, "ask");
	});
});

test("repository mode allows normal skill and development commands", () => {
	withRepository((repository, outside) => {
		for (const command of [
			"pwd",
			"rg TODO . | head -20",
			`diff ${outside}/outside.txt tracked.txt`,
			"ls -la ~/.pi/agent; stat ~/.pi/agent; find ~/.pi/agent -maxdepth 2 -print | sort",
			"python3 -c 'from pathlib import Path\nprint(list(Path(\".\").glob(\"*\")))'",
			"ruby -rjson -e 'puts JSON.generate(ok: true)'",
			"bundle exec rspec",
			"npm test",
			"~/.dots/.agents/skills/dots-check/scripts/scan.rb --unstaged --untracked",
			"cat tracked.txt",
			"sed -i s/a/b/ tracked.txt",
			"printf hello > new.txt",
			"rg TODO > result.txt",
			"rg $(cat query) .",
			"head {../outside/file,tracked.txt}",
		]) {
			assert.equal(call("repository", "bash", { command }, repository.root, repository).kind, "allow", command);
		}
	});
});

test("repository mode asks for high-impact command families", () => {
	withRepository((repository) => {
		for (const command of [
			"sudo touch /tmp/system",
			"doas pacman -Syu",
			"pacman -Syu",
			"brew install jq",
			"brew update",
			"npm install -g ctx7",
			"npm -g install ctx7",
			"asdf plugin remove ruby",
			"find . -delete",
			"find . -exec echo {} ;",
			"find . -fprint results.txt",
			"shred tracked.txt",
			"kill 123",
			"pkill Pi",
			"tmux kill-session -t work",
			"tmux respawn-pane -k -t %1",
			"curl -X POST https://example.test",
			"curl -XPOST https://example.test",
			"curl -dpayload https://example.test",
			"gh api repos/example/repo -X DELETE",
			"gh api repos/example/repo -fstate=closed",
			"gh pr merge 123",
			"npm publish",
			"ssh example.test true",
			"git status\nrm .git/config",
			"sleep 1 & git push origin main",
		]) {
			assert.equal(call("repository", "bash", { command }, repository.root, repository).kind, "ask", command);
		}
	});
});

test("ordinary Git writes are allowed while destructive and remote operations ask", () => {
	withRepository((repository, outside) => {
		for (const command of [
			"git status",
			"git branch --show-current",
			`git -C ${outside} status`,
			"git add tracked.txt",
			"git commit -m 'Update files'",
			"git fetch origin",
			"git worktree list",
		]) {
			assert.equal(call("repository", "bash", { command }, repository.root, repository).kind, "allow", command);
		}
		for (const command of [
			"git commit --amend --no-edit",
			"git checkout feature",
			"git switch -c feature",
			"git branch feature",
			"git branch -r -d origin/old",
			"git reset --hard HEAD~1",
			"git rebase main",
			"git push origin main",
			"CI=1 git push origin main",
			"git remote set-url origin example.test/repo",
			"git stash drop stash@{0}",
			"git worktree remove ../review",
			"git config --remove-section branch.old",
		]) {
			assert.equal(call("repository", "bash", { command }, repository.root, repository).kind, "ask", command);
		}
	});
});

test("SSH grants allow one exact destination for the session", () => {
	withRepository((repository) => {
		const destination = "dev@192.0.2.10";
		const grants = new Set([destination]);
		for (const mode of ["repository", "ask"] as const) {
			for (const command of [
				`ssh ${destination} 'sudo touch /tmp/remote'`,
				`scp /tmp/local ${destination}:/home/svin/remote`,
				`scp ${destination}:/home/svin/remote /tmp/local`,
				`sftp ${destination}`,
				`scp /tmp/local ${destination}:/home/svin/remote && ssh ${destination} true`,
				`scp "$STOW_DIR/.tmux.conf" ${destination}:/tmp/shared.conf && ssh ${destination} 'tmux source-file ~/tmp/shared.conf'`,
			]) {
				assert.equal(
					call(mode, "bash", { command }, repository.root, repository, [], grants).kind,
					"allow",
					command,
				);
			}
		}
		for (const command of [
			"ssh other@example.test true",
			"scp /tmp/local other@example.test:/tmp/remote",
			`scp ${destination}:/tmp/source other@example.test:/tmp/remote`,
			`scp -P 22 /tmp/local ${destination}:/tmp/remote`,
			`scp $STOW_DIR/.tmux.conf ${destination}:/tmp/remote`,
			`scp "$(git push origin main)" ${destination}:/tmp/remote`,
			`scp /tmp/local "$HOST:/tmp/remote"`,
			"sftp other@example.test",
			`sftp -P 22 ${destination}`,
		]) {
			assert.equal(
				call("repository", "bash", { command }, repository.root, repository, [], grants).kind,
				"ask",
				command,
			);
		}
		assert.equal(
			call(
				"repository",
				"bash",
				{ command: `ssh ${destination} true && git push origin main` },
				repository.root,
				repository,
				[],
				grants,
			).kind,
			"ask",
		);
		assert.equal(
			call(
				"repository",
				"bash",
				{ command: `ssh ${destination} "echo $HOME"` },
				repository.root,
				repository,
				[],
				grants,
			).kind,
			"ask",
		);

		assert.equal(getSshDestination(`ssh ${destination} 'sudo reboot'`), destination);
		assert.equal(getSshDestination(`ssh ${destination} true && ssh ${destination} false`), destination);
		assert.equal(
			getSshDestination(`scp /tmp/local ${destination}:/home/svin/remote && ssh ${destination} true`),
			destination,
		);
		assert.equal(
			getSshDestination(`scp "$STOW_DIR/.tmux.conf" ${destination}:/tmp/shared.conf && ssh ${destination} true`),
			destination,
		);
		assert.equal(getSshDestination(`ssh ${destination} true && rm tracked.txt`), undefined);
	});
});

test("rule parsing and shell splitting stay anchored", () => {
	assert.deepEqual(parseRuleList("read grep bash(tool *)"), ["read", "grep", "bash(tool *)"]);
	assert.deepEqual(parseRuleList(["read", "bash(tool *)"]), ["read", "bash(tool *)"]);
	assert.equal(matchRule("bash(tool *)", "bash", "tool run"), true);
	assert.equal(matchRule("bash(tool *)", "bash", "other tool run"), false);
	assert.deepEqual(splitShellCommand("tool 'a|b' && head -1\nrg TODO . & pwd"), [
		"tool 'a|b'",
		"head -1",
		"rg TODO .",
		"pwd",
	]);
	assert.equal(splitShellCommand("tool 'unfinished"), undefined);
});

test("startup ignored-file snapshots are rooted and NUL-safe", () => {
	const root = resolve("/tmp/example-repo");
	assert.deepEqual(
		parseStartupIgnoredPaths(root, ".env\0nested/local.json\0"),
		new Set([join(root, ".env"), join(root, "nested/local.json")]),
	);
});
