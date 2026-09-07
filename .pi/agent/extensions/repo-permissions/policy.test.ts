import assert from "node:assert/strict";
import { mkdtempSync, mkdirSync, realpathSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { homedir, tmpdir } from "node:os";
import { join, resolve } from "node:path";
import test from "node:test";

import {
	decideToolCall,
	getHttpOrigin,
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
	mkdirSync(join(root, "agents_tmp"));
	writeFileSync(join(root, "agents_tmp", "old.scratch"), "scratch\n");
	writeFileSync(join(root, "agents_tmp", "process.pid"), "12345\n");
	writeFileSync(join(root, "agents_tmp", "unsafe.pid"), "-1\n");
	writeFileSync(join(outside, "outside.txt"), "outside\n");
	symlinkSync(outside, join(root, "outside-link"));
	symlinkSync(outside, join(root, "agents_tmp", "outside-link"));
	symlinkSync(".env", join(root, "ignored-alias"));
	symlinkSync("loop", join(root, "loop"));

	try {
		run({ root, startupIgnoredPaths: new Set([join(root, ".env"), join(root, "agents_tmp", "old.scratch")]) }, outside);
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
	httpOrigins: Set<string> = new Set(),
) => decideToolCall({ mode, toolName, input, cwd, repository, skillRules, sshDestinations, httpOrigins });

test("repository mode allows ordinary tools inside and outside the repository", () => {
	withRepository((repository, outside) => {
		const outsideHomePath = join(homedir(), "repo-permissions-outside", "file.txt");
		assert.equal(call("repository", "read", { path: "tracked.txt" }, repository.root, repository).kind, "allow");
		assert.equal(call("repository", "edit", { path: "tracked.txt" }, repository.root, repository).kind, "allow");
		assert.equal(call("repository", "write", { path: "new.txt" }, repository.root, repository).kind, "allow");
		assert.equal(
			call("repository", "read", { path: join(outside, "outside.txt") }, repository.root, repository).kind,
			"allow",
		);
		assert.equal(call("repository", "edit", { path: outsideHomePath }, repository.root, repository).kind, "allow");
		assert.equal(call("repository", "write", { path: outsideHomePath }, repository.root, repository).kind, "allow");
		assert.equal(call("repository", "custom", { payload: "work" }, repository.root, repository).kind, "allow");
	});
});

test("repository modes redirect direct OS-temp mutations to agents_tmp", () => {
	withRepository((repository) => {
		for (const mode of ["repository", "unattended"] as const) {
			for (const toolName of ["edit", "write"]) {
				for (const path of new Set([join(tmpdir(), "agent-owned.tmp"), "/tmp/agent-owned.tmp"])) {
					const decision = call(mode, toolName, { path }, repository.root, repository);
					assert.equal(decision.kind, "block");
					assert.match(decision.reason, /agents_tmp/);
					assert.match(decision.reason, /never commit/i);
				}
			}
		}

		assert.equal(call("repository", "write", { path: "agents_tmp/file" }, repository.root, repository).kind, "allow");
		for (const mode of ["repository", "unattended"] as const) {
			assert.equal(call(mode, "edit", { path: "agents_tmp/old.scratch" }, repository.root, repository).kind, "allow");
		}
		assert.notEqual(call("repository", "edit", { path: "agents_tmp/outside-link/file" }, repository.root, repository).kind, "allow");
		assert.equal(call("repository", "read", { path: join(tmpdir(), "output.log") }, repository.root, repository).kind, "allow");
		assert.equal(call("ask", "write", { path: join(tmpdir(), "output.log") }, repository.root, repository).kind, "ask");
		assert.equal(
			call("unrestricted", "write", { path: join(tmpdir(), "output.log") }, repository.root, repository).kind,
			"allow",
		);
	});
});

test("repository mode allows literal in-repository rm targets", () => {
	withRepository((repository) => {
		for (const command of [
			"rm tracked.txt",
			"rm agents_tmp/old.scratch",
			`cd ${repository.root} && rm agents_tmp/old.scratch`,
			"cd . && rm agents_tmp/old.scratch",
			"rm -rf subdir",
			"rm outside-link",
			"rmdir empty-dir",
			"git rm tracked.txt",
			"find .agents/skills/example -maxdepth 2 -type f -print; rm .agents/skills/example/SKILL.md; rmdir .agents/skills/example",
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
			"rm agents_tmp/outside-link/outside.txt",
			"rm -rf outside-link/",
			"rm -rf outside-link/.",
			"cd /tmp && rm outside.txt",
			"rm \"$TARGET\"",
			"rm *.txt",
			"rm .env",
			"rm .git/config",
			"rm -rf .",
			"rm -rf agents_tmp",
			"cd \"$PWD\" && rm agents_tmp/old.scratch",
			`rmdir ${outside}`,
			"rmdir ../outside",
			"rmdir \"$TARGET\"",
			"rmdir -p nested/empty",
			"rmdir -pv nested/empty",
			"cd /tmp && rmdir empty",
			"rmdir .",
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
			"systemctl --user --failed --no-legend",
			"systemctl --user status example.service",
			"systemctl show example.service --property ActiveState",
			"systemctl is-active example.service",
			"systemctl list-units --type service --state failed",
			"rsync -a --exclude node_modules agents_tmp/scaffold/ ./",
			"cd /home/example/project && rsync -a --exclude node_modules agents_tmp/scaffold/ ./ && git status --short",
			"kill $(cat agents_tmp/process.pid)",
			`cd ${repository.root} && kill $(cat agents_tmp/process.pid) 2>/dev/null`,
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
			"find . -fls results.txt",
			"shred tracked.txt",
			"kill 123",
			"kill -9 $(cat agents_tmp/process.pid)",
			"kill $(cat agents_tmp/missing.pid)",
			"kill $(cat agents_tmp/unsafe.pid)",
			"kill $(cat .env)",
			"pkill Pi",
			"systemctl --user start example.service",
			"systemctl --user restart example.service",
			"systemctl --user enable --now example.service",
			"systemctl --user daemon-reload",
			"systemctl --user set-environment TOKEN=value",
			"systemctl frobnicate example.service",
			"rsync -a --delete source/ destination/",
			"rsync -a --delete-after source/ destination/",
			"rsync -a --remove-source-files source/ destination/",
			"rsync -a source/ example.test:/srv/project/",
			"rsync -a rsync://example.test/module/ destination/",
			"rsync -a -e ssh source/ destination/",
			"rsync -ave ssh source/ destination/",
			"rsync -a --rsh=ssh source/ destination/",
			"rsync -a --rsync-path=/custom/rsync source/ destination/",
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

		const findDecision = call(
			"repository",
			"bash",
			{ command: "find . -type f -exec wc -c {} ;" },
			repository.root,
			repository,
		);
		assert.equal(findDecision.kind, "ask");
		assert.match(findDecision.reason, /list paths first/i);
		assert.match(findDecision.reason, /separate tool call/i);
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
			"git checkout -b feature",
			"git checkout -b feature origin/main",
			"git checkout --no-track -b feature origin/main",
			`git -C ${outside} checkout --no-track -b feature origin/main`,
			"git switch -c feature",
			"git switch -c feature origin/main",
			"git push --set-upstream origin feature",
			"git push -u origin feature",
			`git -C ${outside} push --set-upstream origin feature`,
			"git worktree list",
		]) {
			assert.equal(call("repository", "bash", { command }, repository.root, repository).kind, "allow", command);
		}
		for (const command of [
			"git commit --amend --no-edit",
			"git checkout feature",
			"git checkout -B feature origin/main",
			"git checkout -f -b feature origin/main",
			"git checkout -b \"$BRANCH\" origin/main",
			"git checkout -b feature origin/main -- tracked.txt",
			"git checkout -- tracked.txt",
			"git switch feature",
			"git switch -C feature origin/main",
			"git switch --discard-changes -c feature",
			"git switch -c \"$BRANCH\" origin/main",
			"git branch feature",
			"git branch -r -d origin/old",
			"git reset --hard HEAD~1",
			"git rebase main",
			"git push origin main",
			"CI=1 git push origin main",
			"git push --set-upstream origin main",
			"git push -u origin master",
			"git push -u origin refs/heads/main",
			"git push -u upstream feature",
			"git push -u origin feature other-feature",
			"git push -u origin feature:other-feature",
			"git push -u origin :feature",
			"git push -u origin \"$BRANCH\"",
			"git push -u origin HEAD",
			"git push --tags -u origin feature",
			"git push --force-with-lease -u origin feature",
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
				`ssh -q -o BatchMode=yes -o ConnectTimeout=5 ${destination} true`,
				`scp /tmp/local ${destination}:/home/svin/remote`,
				`scp ${destination}:/home/svin/remote /tmp/local`,
				`sftp ${destination}`,
				`sftp -q -o BatchMode=yes -o ConnectTimeout=5 ${destination}`,
				`scp /tmp/local ${destination}:/home/svin/remote && ssh ${destination} true`,
				`scp "$STOW_DIR/.tmux.conf" ${destination}:/tmp/shared.conf && ssh ${destination} 'tmux source-file ~/tmp/shared.conf'`,
				`scp -q -o BatchMode=yes -o ConnectTimeout=5 /tmp/local ${destination}:/tmp/remote`,
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
			`ssh -o ProxyCommand=helper ${destination} true`,
			`ssh -F alternate-config ${destination} true`,
			"scp /tmp/local other@example.test:/tmp/remote",
			`scp ${destination}:/tmp/source other@example.test:/tmp/remote`,
			`scp -P 22 /tmp/local ${destination}:/tmp/remote`,
			`scp -o ProxyCommand=helper /tmp/local ${destination}:/tmp/remote`,
			`scp -F alternate-config /tmp/local ${destination}:/tmp/remote`,
			`scp -S alternate-ssh /tmp/local ${destination}:/tmp/remote`,
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
		assert.equal(
			getSshDestination(`ssh -q -o BatchMode=yes -o ConnectTimeout=5 ${destination} true`),
			destination,
		);
		assert.equal(getSshDestination(`ssh ${destination} true && ssh ${destination} false`), destination);
		assert.equal(
			getSshDestination(`scp /tmp/local ${destination}:/home/svin/remote && ssh ${destination} true`),
			destination,
		);
		assert.equal(
			getSshDestination(`scp "$STOW_DIR/.tmux.conf" ${destination}:/tmp/shared.conf && ssh ${destination} true`),
			destination,
		);
		assert.equal(
			getSshDestination(`scp -q -o BatchMode=yes -o ConnectTimeout=5 /tmp/local ${destination}:/tmp/remote`),
			destination,
		);
		assert.equal(getSshDestination(`ssh ${destination} true && rm tracked.txt`), undefined);
	});
});

test("HTTP grants allow mutating curl requests to one exact loopback origin", () => {
	withRepository((repository) => {
		const origin = "http://localhost:1337";
		const grants = new Set([origin]);
		for (const mode of ["repository", "ask"] as const) {
			for (const command of [
				"curl -X POST http://localhost:1337/api/items -d '{}'",
				"curl -XPUT http://localhost:1337/api/items/1 -d '{}'",
				"curl -X DELETE http://localhost:1337/api/items/1 && curl -X POST http://localhost:1337/api/items",
			]) {
				assert.equal(
					call(mode, "bash", { command }, repository.root, repository, [], new Set(), grants).kind,
					"allow",
					command,
				);
			}
		}

		for (const command of [
			"curl -X POST http://localhost:3000/api/items",
			"curl -X POST https://localhost:1337/api/items",
			"curl -L -X POST http://localhost:1337/api/items",
			"curl -K curl.conf -X POST http://localhost:1337/api/items",
			"curl --proxy http://localhost:8080 -X POST http://localhost:1337/api/items",
			"HTTP_PROXY=http://localhost:8080 curl -X POST http://localhost:1337/api/items",
			"curl --resolve localhost:1337:192.0.2.10 -X POST http://localhost:1337/api/items",
			"curl --connect-to localhost:1337:192.0.2.10:80 -X POST http://localhost:1337/api/items",
			"curl -H 'Host: admin.localhost' -X POST http://localhost:1337/api/items",
			"curl --unix-socket /var/run/service.sock -X POST http://localhost:1337/api/items",
			"curl -X POST https://example.test/api/items",
			"curl -X POST http://localhost:1337/api/items && kill 123",
		]) {
			assert.equal(
				call("repository", "bash", { command }, repository.root, repository, [], new Set(), grants).kind,
				"ask",
				command,
			);
		}

		assert.equal(
			getHttpOrigin("curl -X POST http://localhost:1337/api/items && curl -X PUT http://localhost:1337/api/other"),
			origin,
		);
		assert.equal(getHttpOrigin("curl -X POST http://127.0.0.1:1337/api/items"), "http://127.0.0.1:1337");
		assert.equal(getHttpOrigin("curl -X POST http://[::1]:1337/api/items"), "http://[::1]:1337");
		assert.equal(getHttpOrigin("curl -X POST https://example.test/api/items"), undefined);
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
