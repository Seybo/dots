import { realpathSync } from "node:fs";

import { parseProtectedPaths, type RepositoryState } from "./policy.ts";

export type GitExecResult = {
	code: number;
	stdout: string;
	stderr?: string;
};

export type GitExec = (
	command: string,
	args: string[],
	options?: { cwd?: string; timeout?: number },
) => Promise<GitExecResult>;

export type RepositoryDiscovery = {
	hasGitRoot: boolean;
	repository?: RepositoryState;
	warning?: string;
};

export async function discoverRepository(cwd: string, exec: GitExec): Promise<RepositoryDiscovery> {
	let rootResult: GitExecResult;
	try {
		rootResult = await exec("git", ["rev-parse", "--show-toplevel"], { cwd, timeout: 5000 });
	} catch {
		return { hasGitRoot: false, warning: "Repository discovery failed; using Ask mode" };
	}
	if (rootResult.code !== 0 || !rootResult.stdout.trim()) return { hasGitRoot: false };

	let root: string;
	try {
		root = realpathSync(rootResult.stdout.trim());
	} catch {
		return { hasGitRoot: false, warning: "Repository path could not be resolved; using Ask mode" };
	}

	let ignoredResult: GitExecResult;
	try {
		ignoredResult = await exec(
			"git",
			["-C", root, "ls-files", "--others", "--ignored", "--exclude-standard", "-z"],
			{ timeout: 15000 },
		);
	} catch {
		return { hasGitRoot: true, warning: "Protected-file snapshot failed; using Ask mode" };
	}
	if (ignoredResult.code !== 0) {
		return { hasGitRoot: true, warning: "Protected-file snapshot failed; using Ask mode" };
	}

	return {
		hasGitRoot: true,
		repository: {
			root,
			protectedPaths: parseProtectedPaths(root, ignoredResult.stdout),
		},
	};
}
