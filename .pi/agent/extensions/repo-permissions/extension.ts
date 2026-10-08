import { appendFileSync, chmodSync, lstatSync, mkdirSync, readFileSync, realpathSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join, resolve } from "node:path";

import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";

import {
	decideToolCall,
	getHttpOrigin,
	getSshDestination,
	getWorktreeAdditions,
	type WorktreeAddition,
	parseRuleList,
	type PermissionMode,
	type RepositoryState,
} from "./policy.ts";
import {
	discoverRepository,
	discoverRepositoryContaining,
	discoverTaskRepository,
	type GitExec,
	type TaskRepositoryResolver,
} from "./repository.ts";

const STATUS_ID = "repo-permissions";
const PROMPT_CHOICES = ["Allow once", "Allow everything for this session", "Reject"];
const REPOSITORY_MODE_CHOICES = ["Repository", "Unattended", "Ask", "Unrestricted"];
const REPOSITORY_RETRY_CHOICES = ["Repository", "Ask", "Unrestricted"];
const BASIC_MODE_CHOICES = ["Ask", "Unrestricted"];
const MAX_PROMPT_DETAIL_LENGTH = 1200;

type FrontmatterParser = (content: string) => Record<string, unknown>;

type PermissionRequestLogEntry = {
	timestamp: string;
	mode: PermissionMode;
	status: "prompted" | "blocked-policy" | "blocked-unattended" | "blocked-no-ui";
	cwd: string;
	tool: string;
	detail: string;
	reason: string;
};

type PermissionRequestLogger = (entry: PermissionRequestLogEntry) => void;

export function registerRepoPermissions(
	pi: ExtensionAPI,
	parseFrontmatter: FrontmatterParser,
	logPermissionRequest: PermissionRequestLogger = appendPermissionRequest,
	resolveTaskRepository: TaskRepositoryResolver = discoverTaskRepository,
): void {
	let mode: PermissionMode = "ask";
	let repository: RepositoryState | undefined;
	let taskRepository: RepositoryState | undefined;
	let hasGitRoot = false;
	let skillRules: string[] | undefined;
	let hasLogWarning = false;
	const sshDestinations = new Set<string>();
	const httpOrigins = new Set<string>();
	const repositoryGrants = new Map<string, RepositoryState>();
	const pendingWorktrees = new Map<string, WorktreeAddition[]>();

	function renderStatus(ctx: ExtensionContext): void {
		const label = mode === "repository" ? "repo" : mode;
		ctx.ui.setStatus(STATUS_ID, ctx.ui.theme.fg("accent", `permissions: ${label}`));
	}

	function setMode(nextMode: PermissionMode, ctx: ExtensionContext): void {
		mode = nextMode;
		renderStatus(ctx);
	}

	async function loadRepository(ctx: ExtensionContext): Promise<void> {
		const exec = (command: string, args: string[], options?: { cwd?: string; timeout?: number }) =>
			pi.exec(command, args, options);
		const discovery = await discoverRepository(ctx.cwd, exec);
		hasGitRoot = discovery.hasGitRoot;
		repository = discovery.repository;
		taskRepository = undefined;
		if (repository) {
			const taskDiscovery = await resolveTaskRepository(repository.root, exec);
			taskRepository = taskDiscovery.repository;
			if (taskDiscovery.warning) ctx.ui.notify(taskDiscovery.warning, "warning");
		}
		setMode(repository ? "repository" : "ask", ctx);
		if (discovery.warning) ctx.ui.notify(discovery.warning, "warning");
	}

	pi.registerCommand("permissions", {
		description: "Select the permission mode for this session",
		handler: async (_args, ctx) => {
			const choices = repository
				? REPOSITORY_MODE_CHOICES
				: hasGitRoot
					? REPOSITORY_RETRY_CHOICES
					: BASIC_MODE_CHOICES;
			const choice = await ctx.ui.select("Permission mode", choices);
			if (choice === "Repository") {
				await loadRepository(ctx);
				if (repository) ctx.ui.notify(`Repository mode: ${repository.root}`, "info");
				return;
			}
			if (choice === "Unattended") setMode("unattended", ctx);
			if (choice === "Ask") setMode("ask", ctx);
			if (choice === "Unrestricted") setMode("unrestricted", ctx);
		},
	});

	pi.on("session_start", async (_event, ctx) => {
		mode = "ask";
		repository = undefined;
		taskRepository = undefined;
		hasGitRoot = false;
		skillRules = undefined;
		hasLogWarning = false;
		sshDestinations.clear();
		httpOrigins.clear();
		repositoryGrants.clear();
		pendingWorktrees.clear();
		await loadRepository(ctx);
	});

	pi.on("tool_result", async (event, ctx) => {
		const additions = pendingWorktrees.get(event.toolCallId);
		pendingWorktrees.delete(event.toolCallId);
		if (event.toolName !== "bash" || event.isError || !additions) return;
		for (const { source, target } of additions) {
			try {
				if (!lstatSync(join(target, ".git")).isFile() || realpathSync(target) !== target) continue;
				const sourceResult = await pi.exec("git", ["rev-parse", "--path-format=absolute", "--git-common-dir"], { cwd: source, timeout: 5000 });
				const targetResult = await pi.exec("git", ["rev-parse", "--path-format=absolute", "--show-toplevel", "--git-common-dir"], { cwd: target, timeout: 5000 });
				if (sourceResult.code !== 0 || targetResult.code !== 0) continue;
				const [root, commonDir] = targetResult.stdout.trim().split("\n");
				if (root !== target || commonDir !== sourceResult.stdout.trim()) continue;
				repositoryGrants.set(target, { root: target, startupIgnoredPaths: new Set(), isDisposableWorktree: true });
				ctx.ui.notify(`Disposable worktree access: ${target}`, "info");
			} catch {
				// Failed verification leaves the normal repository approval boundary intact.
			}
		}
	});

	pi.on("session_shutdown", (_event, ctx) => {
		ctx.ui.setStatus(STATUS_ID, undefined);
	});

	pi.on("tool_call", async (event, ctx) => {
		const input = event.input as Record<string, unknown>;
		const command = event.toolName === "bash" && typeof input.command === "string" ? input.command : undefined;
		const sshDestination = command ? getSshDestination(command) : undefined;
		const repositories = repository
			? [repository, ...(taskRepository ? [taskRepository] : []), ...repositoryGrants.values()]
			: [];
		const decision = decideToolCall({
			mode,
			toolName: event.toolName,
			input,
			cwd: ctx.cwd,
			repositories,
			skillRules: (skillRules ??= getSkillRules(pi, parseFrontmatter)),
			sshDestinations,
			httpOrigins,
		});

		function recordWorktreeCreation(): void {
			if (command && repository) {
				const additions = getWorktreeAdditions(command, ctx.cwd).filter(({ target }) => {
					try {
						lstatSync(target);
						return false;
					} catch (error) {
						return error instanceof Error && "code" in error && (error as NodeJS.ErrnoException).code === "ENOENT";
					}
				});
				if (additions.length) pendingWorktrees.set(event.toolCallId, additions);
			}
		}

		if (decision.kind === "allow") {
			recordWorktreeCreation();
			return;
		}

		try {
			logPermissionRequest({
				timestamp: new Date().toISOString(),
				mode,
				status:
					decision.kind === "block"
						? "blocked-policy"
						: mode === "unattended"
							? "blocked-unattended"
							: ctx.hasUI
								? "prompted"
								: "blocked-no-ui",
				cwd: ctx.cwd,
				tool: event.toolName,
				detail: truncatePromptDetail(getToolDetail(event.toolName, input)),
				reason: decision.reason,
			});
		} catch (error) {
			if (!hasLogWarning) {
				hasLogWarning = true;
				ctx.ui.notify(`Could not write the permission request log: ${String(error)}`, "warning");
			}
		}

		if (decision.kind === "block") return { block: true, reason: decision.reason };
		if (mode === "unattended") {
			return {
				block: true,
				reason: `Blocked in Unattended mode: ${decision.reason} Continue with permitted work and report this blocked operation.`,
			};
		}
		if (!ctx.hasUI) {
			return {
				block: true,
				reason: `Blocked because approval is unavailable: ${decision.reason}`,
			};
		}

		const sshChoice = sshDestination ? `Allow SSH access to ${sshDestination} for this session` : undefined;
		const httpOrigin = command
			? grantableHttpOrigin(
					command,
					mode,
					input,
					ctx.cwd,
					repositories,
					skillRules,
					sshDestinations,
					httpOrigins,
				)
			: undefined;
		const httpChoice = httpOrigin ? `Allow HTTP access to ${httpOrigin} for this session` : undefined;
		const grantRepository = await grantableRepository(
			event.toolName,
			input,
			ctx.cwd,
			mode,
			repositories,
			skillRules,
			sshDestinations,
			httpOrigins,
			(command, args, options) => pi.exec(command, args, options),
		);
		const repositoryChoice = grantRepository
			? `Allow changes in ${grantRepository.root} for this session`
			: undefined;
		const sessionChoice = sshChoice ?? httpChoice ?? repositoryChoice;
		const choices = sessionChoice
			? ["Allow once", sessionChoice, "Allow everything for this session", "Reject"]
			: PROMPT_CHOICES;
		const choice = await ctx.ui.select(formatPrompt(event.toolName, input, decision.reason), choices);
		if (choice === "Allow once") {
			recordWorktreeCreation();
			return;
		}
		if (sshDestination && choice === sshChoice) {
			sshDestinations.add(sshDestination);
			ctx.ui.notify(`SSH access to ${sshDestination} is allowed for this session.`, "info");
			return;
		}
		if (httpOrigin && choice === httpChoice) {
			httpOrigins.add(httpOrigin);
			ctx.ui.notify(`HTTP access to ${httpOrigin} is allowed for this session.`, "info");
			return;
		}
		if (grantRepository && choice === repositoryChoice) {
			repositoryGrants.set(grantRepository.root, grantRepository);
			ctx.ui.notify(`Changes in ${grantRepository.root} are allowed for this session.`, "info");
			return;
		}
		if (choice === "Allow everything for this session") {
			recordWorktreeCreation();
			setMode("unrestricted", ctx);
			return;
		}

		ctx.abort();
		return { block: true, reason: "Rejected by user" };
	});
}

async function grantableRepository(
	toolName: string,
	input: Record<string, unknown>,
	cwd: string,
	mode: PermissionMode,
	repositories: RepositoryState[],
	skillRules: string[],
	sshDestinations: Set<string>,
	httpOrigins: Set<string>,
	exec: GitExec,
): Promise<RepositoryState | undefined> {
	if (
		repositories.length === 0 ||
		!["edit", "write"].includes(toolName) ||
		typeof input.path !== "string"
	) {
		return undefined;
	}

	const discovery = await discoverRepositoryContaining(resolve(cwd, input.path), exec);
	const candidate = discovery.repository;
	if (!candidate || repositories.some((allowed) => allowed.root === candidate.root)) return undefined;

	const decision = decideToolCall({
		mode,
		toolName,
		input,
		cwd,
		repositories: [...repositories, candidate],
		skillRules,
		sshDestinations,
		httpOrigins,
	});
	return decision.kind === "allow" ? candidate : undefined;
}

function grantableHttpOrigin(
	command: string,
	mode: PermissionMode,
	input: Record<string, unknown>,
	cwd: string,
	repositories: RepositoryState[],
	skillRules: string[],
	sshDestinations: Set<string>,
	httpOrigins: Set<string>,
): string | undefined {
	const origin = getHttpOrigin(command);
	if (!origin) return undefined;

	const candidateOrigins = new Set(httpOrigins);
	candidateOrigins.add(origin);
	const decision = decideToolCall({
		mode,
		toolName: "bash",
		input,
		cwd,
		repositories,
		skillRules,
		sshDestinations,
		httpOrigins: candidateOrigins,
	});
	return decision.kind === "allow" ? origin : undefined;
}

export function getPermissionLogPath(): string {
	const defaultStateHome =
		process.platform === "darwin" ? join(homedir(), "Library", "Logs") : join(homedir(), ".local", "state");
	return join(process.env.XDG_STATE_HOME ?? defaultStateHome, "pi", "repo-permissions.jsonl");
}

function appendPermissionRequest(entry: PermissionRequestLogEntry): void {
	const path = getPermissionLogPath();
	mkdirSync(dirname(path), { recursive: true, mode: 0o700 });
	appendFileSync(path, `${JSON.stringify(entry)}\n`, { encoding: "utf8", mode: 0o600 });
	chmodSync(path, 0o600);
}

function formatPrompt(toolName: string, input: Record<string, unknown>, reason: string): string {
	return `${toolName}: ${truncatePromptDetail(getToolDetail(toolName, input))}\n\n${reason}`;
}

function getToolDetail(toolName: string, input: Record<string, unknown>): string {
	if (toolName === "bash" && typeof input.command === "string") return input.command;
	if (typeof input.path === "string") return input.path;
	return JSON.stringify(input);
}

function truncatePromptDetail(detail: string): string {
	if (detail.length <= MAX_PROMPT_DETAIL_LENGTH) return detail;
	return `${detail.slice(0, MAX_PROMPT_DETAIL_LENGTH)}\n… <truncated ${detail.length - MAX_PROMPT_DETAIL_LENGTH} chars>`;
}

function getSkillRules(pi: ExtensionAPI, parseFrontmatter: FrontmatterParser): string[] {
	const skills = pi.getCommands().filter(
		(command) =>
			command.source === "skill" &&
			command.sourceInfo.origin === "top-level" &&
			(command.sourceInfo.scope === "user" || command.sourceInfo.scope === "project"),
	);

	return [
		...new Set(
			skills.flatMap((skill) => {
				try {
					const frontmatter = parseFrontmatter(readFileSync(skill.sourceInfo.path, "utf8"));
					return parseRuleList(frontmatter["allowed-tools"]);
				} catch {
					return [];
				}
			}),
		),
	];
}
