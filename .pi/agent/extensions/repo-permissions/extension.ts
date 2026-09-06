import { appendFileSync, chmodSync, mkdirSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join } from "node:path";

import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";

import {
	decideToolCall,
	getSshDestination,
	parseRuleList,
	type PermissionMode,
	type RepositoryState,
} from "./policy.ts";
import { discoverRepository } from "./repository.ts";

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
	status: "prompted" | "blocked-unattended" | "blocked-no-ui";
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
): void {
	let mode: PermissionMode = "ask";
	let repository: RepositoryState | undefined;
	let hasGitRoot = false;
	let skillRules: string[] | undefined;
	let hasLogWarning = false;
	const sshDestinations = new Set<string>();

	function renderStatus(ctx: ExtensionContext): void {
		const label = mode === "repository" ? "repo" : mode;
		ctx.ui.setStatus(STATUS_ID, ctx.ui.theme.fg("accent", `permissions: ${label}`));
	}

	function setMode(nextMode: PermissionMode, ctx: ExtensionContext): void {
		mode = nextMode;
		renderStatus(ctx);
	}

	async function loadRepository(ctx: ExtensionContext): Promise<void> {
		const discovery = await discoverRepository(ctx.cwd, (command, args, options) =>
			pi.exec(command, args, options),
		);
		hasGitRoot = discovery.hasGitRoot;
		repository = discovery.repository;
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
		hasGitRoot = false;
		skillRules = undefined;
		hasLogWarning = false;
		sshDestinations.clear();
		await loadRepository(ctx);
	});

	pi.on("session_shutdown", (_event, ctx) => {
		ctx.ui.setStatus(STATUS_ID, undefined);
	});

	pi.on("tool_call", async (event, ctx) => {
		const input = event.input as Record<string, unknown>;
		const command = event.toolName === "bash" && typeof input.command === "string" ? input.command : undefined;
		const sshDestination = command ? getSshDestination(command) : undefined;
		const decision = decideToolCall({
			mode,
			toolName: event.toolName,
			input,
			cwd: ctx.cwd,
			repository,
			skillRules: (skillRules ??= getSkillRules(pi, parseFrontmatter)),
			sshDestinations,
		});

		if (decision.kind === "allow") return;
		if (decision.kind === "block") return { block: true, reason: decision.reason };

		try {
			logPermissionRequest({
				timestamp: new Date().toISOString(),
				mode,
				status: mode === "unattended" ? "blocked-unattended" : ctx.hasUI ? "prompted" : "blocked-no-ui",
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
		const choices = sshChoice
			? ["Allow once", sshChoice, "Allow everything for this session", "Reject"]
			: PROMPT_CHOICES;
		const choice = await ctx.ui.select(formatPrompt(event.toolName, input, decision.reason), choices);
		if (choice === "Allow once") return;
		if (sshDestination && choice === sshChoice) {
			sshDestinations.add(sshDestination);
			ctx.ui.notify(`SSH access to ${sshDestination} is allowed for this session.`, "info");
			return;
		}
		if (choice === "Allow everything for this session") {
			setMode("unrestricted", ctx);
			return;
		}

		ctx.abort();
		return { block: true, reason: "Rejected by user" };
	});
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
