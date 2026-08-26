import { spawn } from "node:child_process";
import { stat } from "node:fs/promises";
import { homedir } from "node:os";
import { basename, isAbsolute, resolve } from "node:path";

export type FileReference = {
	path: string;
	line?: number;
	column?: number;
};

export type TmuxPane = {
	id: string;
	command: string;
};

export function resolveFileReference(reference: string, cwd: string, home = homedir()): FileReference {
	const location = reference.match(/^(.*?):(\d+)(?::(\d+))?$/);
	const rawPath = location?.[1] ?? reference;
	const path = rawPath.startsWith("~/")
		? resolve(home, rawPath.slice(2))
		: isAbsolute(rawPath)
			? rawPath
			: resolve(cwd, rawPath);

	return {
		path,
		...(location ? { line: Number(location[2]), ...(location[3] ? { column: Number(location[3]) } : {}) } : {}),
	};
}

function shellQuote(value: string): string {
	return `'${value.replaceAll("'", "'\\''")}'`;
}

export function buildNvimCommand(reference: FileReference): string {
	const cursor = reference.line
		? `${shellQuote(`+call cursor(${reference.line}, ${reference.column ?? 1})`)} `
		: "";
	return `nvim ${cursor}-- ${shellQuote(reference.path)}`;
}

export function selectIdlePane(
	panes: TmuxPane[],
	currentPaneId: string,
	shellCommand: string,
): string | undefined {
	return panes.find((pane) => pane.id !== currentPaneId && pane.command === shellCommand)?.id;
}

function runTmux(args: string[]): Promise<string> {
	return new Promise((resolveOutput, reject) => {
		const child = spawn("tmux", args);
		let stdout = "";
		let stderr = "";
		let isSettled = false;

		child.stdout.on("data", (chunk) => {
			stdout += String(chunk);
		});
		child.stderr.on("data", (chunk) => {
			stderr += String(chunk);
		});
		child.on("error", (error) => {
			if (isSettled) return;
			isSettled = true;
			reject(error);
		});
		child.on("close", (code) => {
			if (isSettled) return;
			isSettled = true;
			if (code === 0) resolveOutput(stdout);
			else reject(new Error(stderr.trim() || `tmux exited with code ${code}`));
		});
	});
}

export async function openFileInAdjacentPane(reference: string, cwd: string): Promise<void> {
	const currentPaneId = process.env.TMUX_PANE;
	if (!currentPaneId) throw new Error("Pi is not running inside tmux");

	const file = resolveFileReference(reference, cwd);
	let fileStat;
	try {
		fileStat = await stat(file.path);
	} catch {
		throw new Error(`File does not exist: ${file.path}`);
	}
	if (!fileStat.isFile()) throw new Error(`Not a file: ${file.path}`);

	const windowId = (
		await runTmux(["display-message", "-p", "-t", currentPaneId, "-F", "#{window_id}"])
	).trim();
	const paneOutput = await runTmux([
		"list-panes",
		"-t",
		windowId,
		"-F",
		"#{pane_id}\t#{pane_current_command}",
	]);
	const panes = paneOutput
		.trim()
		.split("\n")
		.filter(Boolean)
		.map((line) => {
			const [id, command] = line.split("\t");
			return { id: id!, command: command! };
		});
	const adjacentPanes = panes.filter((pane) => pane.id !== currentPaneId);
	if (adjacentPanes.length === 0) throw new Error("The current tmux window has no adjacent pane");

	const shellCommand = basename(process.env.SHELL ?? "");
	if (!shellCommand) throw new Error("SHELL is not set");
	const targetPaneId = selectIdlePane(adjacentPanes, currentPaneId, shellCommand);
	if (!targetPaneId) throw new Error("Every adjacent pane is running a process");

	await runTmux(["send-keys", "-t", targetPaneId, "-l", buildNvimCommand(file)]);
	await runTmux(["send-keys", "-t", targetPaneId, "Enter"]);
	await runTmux(["select-pane", "-t", targetPaneId]);
}
