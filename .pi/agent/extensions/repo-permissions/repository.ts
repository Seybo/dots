import { lstatSync, realpathSync } from "node:fs";
import { homedir } from "node:os";
import { basename, dirname, isAbsolute, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import { parseStartupIgnoredPaths, type RepositoryState } from "./policy.ts";

export type GitExecResult = {
	code: number;
	stdout: string;
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

export type TaskRepositoryDiscovery = {
	repository?: RepositoryState;
	warning?: string;
};

export type TaskRepositoryOptions = {
	registryPath?: string;
	resolverPath?: string;
	devRoot?: string;
	stowDir?: string;
};

export type TaskRepositoryResolver = (
	primaryRoot: string,
	exec: GitExec,
) => Promise<TaskRepositoryDiscovery>;

export async function discoverTaskRepository(
	primaryRoot: string,
	exec: GitExec,
	options: TaskRepositoryOptions = {},
): Promise<TaskRepositoryDiscovery> {
	const registryPath =
		options.registryPath ?? join(homedir(), ".ai", "skills-shared", "components", "projects.yml");
	const resolverPath =
		options.resolverPath ?? fileURLToPath(new URL("resolve_task_root.rb", import.meta.url));
	const devRoot = options.devRoot ?? process.env.DEV_ROOT;
	const stowDir = options.stowDir ?? process.env.STOW_DIR;
	if (!devRoot || !stowDir) {
		return {
			warning: "Project task repository discovery needs DEV_ROOT and STOW_DIR; companion access is unavailable",
		};
	}

	let result: GitExecResult;
	try {
		result = await exec("ruby", [resolverPath, registryPath, primaryRoot, devRoot, stowDir], {
			timeout: 5000,
		});
	} catch {
		return {
			warning: "Project task repository discovery failed; companion access is unavailable",
		};
	}
	if (result.code !== 0) {
		return {
			warning: "Project task repository discovery failed; companion access is unavailable",
		};
	}

	const output = result.stdout.trim();
	if (!output) return {};
	if (output.includes("\n") || !isAbsolute(output) || basename(output) !== "_tasks") {
		return {
			warning: "Project task repository discovery returned an invalid path; companion access is unavailable",
		};
	}

	let taskRoot: string;
	try {
		taskRoot = join(realpathSync(dirname(output)), "_tasks");
		const stat = lstatSync(output);
		if (stat.isSymbolicLink()) {
			return {
				warning: "The registered task root is a symbolic link; companion access is unavailable",
			};
		}
		if (!stat.isDirectory()) {
			return {
				warning: "The registered task root is not a directory; companion access is unavailable",
			};
		}
	} catch (error) {
		if (!isMissingPathError(error)) {
			return {
				warning: "The registered task root could not be resolved; companion access is unavailable",
			};
		}
		try {
			taskRoot = join(realpathSync(dirname(output)), "_tasks");
		} catch {
			return {
				warning: "The registered task root parent could not be resolved; companion access is unavailable",
			};
		}
		return { repository: { root: taskRoot, startupIgnoredPaths: new Set() } };
	}

	const discovery = await discoverRepository(taskRoot, exec);
	if (!discovery.repository) {
		return {
			warning: discovery.hasGitRoot
				? "The task repository ignored-file snapshot failed; companion access is unavailable"
				: "The registered task root is not a Git repository; companion access is unavailable",
		};
	}
	if (discovery.repository.root !== taskRoot) {
		return {
			warning: "The registered task root is not an independent Git repository; companion access is unavailable",
		};
	}
	return { repository: discovery.repository };
}

export async function discoverRepositoryContaining(
	target: string,
	exec: GitExec,
): Promise<RepositoryDiscovery> {
	let candidate = resolve(target);
	while (true) {
		try {
			const stat = lstatSync(candidate);
			return discoverRepository(stat.isDirectory() ? candidate : dirname(candidate), exec);
		} catch (error) {
			if (!(error instanceof Error && "code" in error && (error as NodeJS.ErrnoException).code === "ENOENT")) {
				return { hasGitRoot: false };
			}
		}
		const parent = dirname(candidate);
		if (parent === candidate) return { hasGitRoot: false };
		candidate = parent;
	}
}

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
		return { hasGitRoot: true, warning: "Git-ignored file snapshot failed; using Ask mode" };
	}
	if (ignoredResult.code !== 0) {
		return { hasGitRoot: true, warning: "Git-ignored file snapshot failed; using Ask mode" };
	}

	return {
		hasGitRoot: true,
		repository: {
			root,
			startupIgnoredPaths: parseStartupIgnoredPaths(root, ignoredResult.stdout),
		},
	};
}

function isMissingPathError(error: unknown): boolean {
	return error instanceof Error && "code" in error && (error as NodeJS.ErrnoException).code === "ENOENT";
}
