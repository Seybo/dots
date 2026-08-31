import { lstatSync, readlinkSync, realpathSync } from "node:fs";
import { homedir, tmpdir } from "node:os";
import { basename, dirname, isAbsolute, join, relative, resolve, sep } from "node:path";

export type PermissionMode = "repository" | "unattended" | "ask" | "unrestricted";

export type PermissionDecision =
	| { kind: "allow" }
	| { kind: "ask"; reason: string }
	| { kind: "block"; reason: string };

export type RepositoryState = {
	root: string;
	startupIgnoredPaths: Set<string>;
};

type ToolCall = {
	mode: PermissionMode;
	toolName: string;
	input: Record<string, unknown>;
	cwd: string;
	repository?: RepositoryState;
	skillRules: string[];
	sshDestinations: Set<string>;
};

type PathInfo = {
	lexical: string;
	canonical: string;
};

const ALLOW: PermissionDecision = { kind: "allow" };
const PI_CLIPBOARD_IMAGE = /^pi-clipboard-[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\.png$/i;
const ASK_COMMANDS = new Set([
	"dd",
	"diskutil",
	"doas",
	"exec",
	"kill",
	"killall",
	"launchctl",
	"mkfs",
	"pkill",
	"pacman",
	"rsync",
	"security",
	"service",
	"shred",
	"su",
	"sudo",
	"truncate",
	"unlink",
	"wipefs",
]);
const GUARDED_BRANCH_ARGUMENTS = new Set([
	"-d",
	"-D",
	"-m",
	"-M",
	"-c",
	"-C",
	"-f",
	"--delete",
	"--move",
	"--copy",
	"--force",
]);
const GUARDED_GIT_COMMANDS = new Set([
	"bisect",
	"checkout",
	"cherry-pick",
	"clean",
	"gc",
	"merge",
	"mv",
	"prune",
	"pull",
	"push",
	"rebase",
	"repack",
	"reset",
	"restore",
	"revert",
	"switch",
	"update-ref",
]);
const READ_ONLY_SYSTEMCTL_COMMANDS = new Set([
	"cat",
	"get-default",
	"help",
	"is-active",
	"is-enabled",
	"is-failed",
	"is-system-running",
	"list-automounts",
	"list-dependencies",
	"list-jobs",
	"list-machines",
	"list-paths",
	"list-sockets",
	"list-timers",
	"list-unit-files",
	"list-units",
	"show",
	"show-environment",
	"status",
]);
const SYSTEMCTL_OPTIONS_WITH_VALUE = new Set([
	"-H",
	"-M",
	"-n",
	"-o",
	"-p",
	"-t",
	"--host",
	"--image",
	"--lines",
	"--machine",
	"--output",
	"--property",
	"--root",
	"--state",
	"--type",
]);
const GUARDED_TMUX_COMMANDS = new Set([
	"break-pane",
	"join-pane",
	"link-window",
	"move-pane",
	"move-window",
	"new-session",
	"new-window",
	"select-layout",
	"split-window",
	"swap-pane",
	"unlink-window",
]);

export function parseStartupIgnoredPaths(root: string, output: string): Set<string> {
	return new Set(
		output
			.split("\0")
			.filter(Boolean)
			.map((entry) => resolve(root, entry)),
	);
}

export function parseRuleList(value: unknown): string[] {
	const entries = Array.isArray(value) ? value : typeof value === "string" ? [value] : [];
	return entries.filter((entry): entry is string => typeof entry === "string").flatMap(splitRuleString);
}

export function matchRule(rule: string, toolName: string, argValue: string): boolean {
	const match = rule.match(/^([^(]+)\((.*)\)$/s);
	const toolPattern = match?.[1] ?? rule;
	const argPattern = match?.[2];

	if (!matchPattern(toolPattern, toolName)) return false;
	return argPattern === undefined || matchPattern(argPattern, argValue);
}

export function splitShellCommand(command: string): string[] | undefined {
	const segments: string[] = [];
	let current = "";
	let quote: "'" | '"' | undefined;
	let isEscaped = false;

	for (let index = 0; index < command.length; index++) {
		const character = command[index]!;
		if (isEscaped) {
			current += character;
			isEscaped = false;
			continue;
		}
		if (character === "\\" && quote !== "'") {
			current += character;
			isEscaped = true;
			continue;
		}
		if ((character === "'" || character === '"') && (!quote || quote === character)) {
			quote = quote ? undefined : character;
			current += character;
			continue;
		}
		if (quote) {
			current += character;
			continue;
		}

		const pair = command.slice(index, index + 2);
		if (pair === "&&" || pair === "||") {
			pushSegment(segments, current);
			current = "";
			index++;
			continue;
		}
		if (["|", "&", ";", "\n", "\r"].includes(character)) {
			pushSegment(segments, current);
			current = "";
			continue;
		}
		current += character;
	}

	if (quote || isEscaped) return undefined;
	pushSegment(segments, current);
	return segments.length > 0 ? segments : undefined;
}

export function decideToolCall(call: ToolCall): PermissionDecision {
	if (call.mode === "unrestricted") return ALLOW;

	const argValue = getMatchValue(call.toolName, call.input);
	if (call.toolName === "read" && argValue && isPiClipboardImage(argValue, call.cwd)) return ALLOW;
	if ((call.toolName === "edit" || call.toolName === "write") && !argValue) {
		return { kind: "ask", reason: `${call.toolName} has no path to evaluate.` };
	}

	if ((call.toolName === "edit" || call.toolName === "write") && call.repository && argValue) {
		if (call.mode === "repository" || call.mode === "unattended") {
			const tempDecision = decideOsTempMutation(call.toolName, argValue, call.cwd, call.repository);
			if (tempDecision) return tempDecision;
		}
		const mutationDecision = decideDirectMutation(argValue, call.cwd, call.repository);
		if (mutationDecision) return mutationDecision;
	}

	if (call.toolName === "bash" && argValue) {
		const guardedDecision = decideGuardedBash(
			argValue,
			call.cwd,
			call.repository,
			call.sshDestinations,
		);
		if (guardedDecision) return guardedDecision;
	}

	if (call.mode === "ask") {
		if (
			call.toolName === "bash" &&
			argValue &&
			isAllowedBySessionSsh(argValue, call.sshDestinations)
		) {
			return ALLOW;
		}
		return isAllowedBySkill(call.toolName, argValue, call.skillRules)
			? ALLOW
			: { kind: "ask", reason: "Ask mode requires approval." };
	}

	if (!call.repository) return { kind: "ask", reason: "Repository mode is unavailable." };
	if (call.toolName === "bash" && !argValue) {
		return { kind: "ask", reason: "Bash has no command to evaluate." };
	}
	return ALLOW;
}

export function getSshDestination(command: string): string | undefined {
	const segments = splitShellCommand(command);
	if (!segments) return undefined;

	const destinations = segments.map(parseSshAccessSegment);
	const destination = destinations[0];
	return destination && destinations.every((candidate) => candidate === destination) ? destination : undefined;
}

function decideOsTempMutation(
	toolName: string,
	rawPath: string,
	cwd: string,
	repository: RepositoryState,
): PermissionDecision | undefined {
	const pathInfo = resolvePathInfo(rawPath, cwd);
	if (!pathInfo || isInside(repository.root, pathInfo.canonical)) return undefined;

	const isOsTemp = [tmpdir(), "/tmp"]
		.map(canonicalPath)
		.some((root) => root && isInside(root, pathInfo.canonical));
	if (!isOsTemp) return undefined;

	return {
		kind: "block",
		reason: `Direct ${toolName} targets in OS temporary directories are blocked. Use ${join(repository.root, "agents_tmp")} for agent-owned temporary files. Never commit agents_tmp.`,
	};
}

function decideDirectMutation(
	rawPath: string,
	cwd: string,
	repository: RepositoryState,
): PermissionDecision | undefined {
	const pathInfo = resolvePathInfo(rawPath, cwd);
	if (!pathInfo) return { kind: "ask", reason: `Could not resolve ${rawPath} safely.` };

	if (
		repository.startupIgnoredPaths.has(pathInfo.lexical) ||
		repository.startupIgnoredPaths.has(pathInfo.canonical)
	) {
		return {
			kind: "ask",
			reason: `The target of ${rawPath} was untracked and Git-ignored when Repository mode started.`,
		};
	}

	if (
		isGitMetadata(repository.root, pathInfo.lexical) ||
		isGitMetadata(repository.root, pathInfo.canonical)
	) {
		return { kind: "ask", reason: `The target of ${rawPath} is Git metadata and requires approval.` };
	}
	return undefined;
}

function decideGuardedBash(
	command: string,
	cwd: string,
	repository: RepositoryState | undefined,
	sshDestinations: Set<string>,
): PermissionDecision | undefined {
	let hasChangedDirectory = false;
	for (const segment of splitShellCommand(command) ?? [command]) {
		const commandTokens = getCommandTokens(segment);
		const reason = guardedSegmentReason(
			segment,
			commandTokens,
			cwd,
			repository,
			sshDestinations,
			hasChangedDirectory,
		);
		if (reason) return { kind: "ask", reason };
		const commandName = commandTokens ? basename(commandTokens[0]!) : undefined;
		if (commandName && ["cd", "popd", "pushd"].includes(commandName)) hasChangedDirectory = true;
	}
	return undefined;
}

function guardedSegmentReason(
	segment: string,
	commandTokens: string[] | undefined,
	cwd: string,
	repository: RepositoryState | undefined,
	sshDestinations: Set<string>,
	hasChangedDirectory: boolean,
): string | undefined {
	if (!commandTokens) return undefined;

	const command = basename(commandTokens[0]!);
	const args = commandTokens.slice(1);
	if (["scp", "sftp", "ssh"].includes(command)) {
		return isAllowedSshAccessSegment(segment, sshDestinations)
			? undefined
			: "SSH access requires destination approval.";
	}
	if (command === "systemctl") {
		return isReadOnlySystemctl(args) ? undefined : "This systemctl operation requires approval.";
	}
	if (ASK_COMMANDS.has(command)) return `${command} requires approval.`;
	if (command === "rm" || command === "rmdir") {
		if (command === "rmdir" && args.some(hasParentRemovalFlag)) {
			return "rmdir parent removal requires approval.";
		}
		return guardedDeletionReason(command, segment, args, cwd, repository, hasChangedDirectory);
	}
	if (args.some((arg) => arg.startsWith("--force"))) return `${command} --force requires approval.`;
	if (command === "find" && args.some(isMutatingFindArgument)) return "find mutation requires approval.";
	if (command === "git" && isGuardedGit(commandTokens)) return "This Git operation requires approval.";
	if (command === "tmux" && args.some(isGuardedTmuxCommand)) return "This tmux operation requires approval.";
	if (command === "curl" && isMutatingCurl(args)) return "This curl request can mutate an external service.";
	if (command === "gh" && isMutatingGh(args)) return "This GitHub operation can mutate remote state.";
	if (isHostPackageMutation(command, args)) return "Global package changes require approval.";
	if (isPublish(command, args)) return "Publishing requires approval.";
	return undefined;
}

function guardedDeletionReason(
	command: "rm" | "rmdir",
	segment: string,
	args: string[],
	cwd: string,
	repository: RepositoryState | undefined,
	hasChangedDirectory: boolean,
): string | undefined {
	if (!repository) return `${command} targets require an active repository.`;
	if (hasChangedDirectory || hasUnsafeShellSyntax(segment)) {
		return `${command} targets cannot be resolved safely from this shell command.`;
	}

	const targets = deletionTargets(args);
	if (targets.length === 0) return `${command} has no literal target to evaluate.`;

	const canonicalCwd = canonicalPath(cwd);
	if (!canonicalCwd) return "rm working directory cannot be resolved safely.";
	for (const target of targets) {
		const targetInfo = resolveShellPathInfo(target, canonicalCwd);
		const canonicalParent = targetInfo ? canonicalPath(dirname(targetInfo.lexical)) : undefined;
		const deletionPath = canonicalParent && targetInfo
			? join(canonicalParent, basename(targetInfo.lexical))
			: undefined;
		if (
			!deletionPath ||
			deletionPath === repository.root ||
			!isInside(repository.root, deletionPath) ||
			(deletionMayDereferenceTarget(target) && !isInside(repository.root, targetInfo.canonical))
		) {
			return `${command} target ${target} resolves outside the repository or cannot be evaluated safely.`;
		}
		if (isGitMetadata(repository.root, deletionPath)) {
			return `${command} target ${target} is Git metadata and requires approval.`;
		}
		if (
			[...repository.startupIgnoredPaths].some(
				(ignoredPath) => ignoredPath === deletionPath || isInside(deletionPath, ignoredPath),
			)
		) {
			return `${command} target ${target} contains a file that was untracked and Git-ignored when Repository mode started.`;
		}
	}
	return undefined;
}

function hasParentRemovalFlag(arg: string): boolean {
	return arg === "--parents" || (arg.startsWith("-") && !arg.startsWith("--") && arg.slice(1).includes("p"));
}

function deletionTargets(args: string[]): string[] {
	const separator = args.indexOf("--");
	if (separator !== -1) return args.slice(separator + 1);
	return args.filter((arg) => arg === "-" || !arg.startsWith("-"));
}

function deletionMayDereferenceTarget(target: string): boolean {
	return target === "." || target === ".." || /\/$|\/\.{1,2}\/?$/.test(target);
}

function getCommandTokens(segment: string): string[] | undefined {
	const tokens = tokenizeShellSegment(segment);
	if (!tokens || tokens.length === 0) return undefined;
	const commandIndex = tokens.findIndex((token) => !/^[a-z_][a-z0-9_]*=/i.test(token));
	return commandIndex === -1 ? undefined : tokens.slice(commandIndex);
}

function isReadOnlySystemctl(args: string[]): boolean {
	for (let index = 0; index < args.length; index++) {
		const arg = args[index]!;
		if (SYSTEMCTL_OPTIONS_WITH_VALUE.has(arg)) {
			index++;
			continue;
		}
		if (arg.startsWith("-")) continue;
		return READ_ONLY_SYSTEMCTL_COMMANDS.has(arg);
	}
	return true;
}

function isMutatingFindArgument(arg: string): boolean {
	return ["-delete", "--delete", "-exec", "-execdir", "-ok", "-okdir"].includes(arg) || arg.startsWith("-fprint");
}

function isGuardedGit(tokens: string[]): boolean {
	const parsed = parseGitCommand(tokens);
	if (!parsed) return false;
	const { command, args } = parsed;

	if (GUARDED_GIT_COMMANDS.has(command)) return true;
	if (command === "commit") return args.includes("--amend");
	if (command === "branch") {
		if (args.some((arg) => GUARDED_BRANCH_ARGUMENTS.has(arg))) return true;
		return !(args.length === 0 || ["--show-current", "--list", "-a", "-r", "-v", "-vv"].includes(args[0]!));
	}
	if (command === "tag") return !(args.length === 0 || ["--list", "-l"].includes(args[0]!));
	if (command === "stash") return !["list", "show"].includes(args[0] ?? "");
	if (command === "remote") return ![undefined, "-v", "show", "get-url"].includes(args[0]);
	if (command === "reflog") return ["delete", "expire"].includes(args[0] ?? "");
	if (command === "worktree") return args[0] !== "list";
	if (command === "submodule") return !["status", "summary"].includes(args[0] ?? "");
	if (command === "notes") return !["list", "show"].includes(args[0] ?? "");
	if (command === "config") return isMutatingGitConfig(args);
	return false;
}

function parseGitCommand(tokens: string[]): { command: string; args: string[] } | undefined {
	let index = 1;
	while (index < tokens.length && tokens[index]!.startsWith("-")) {
		const option = tokens[index]!;
		index += ["-C", "-c", "--git-dir", "--namespace", "--work-tree"].includes(option) ? 2 : 1;
	}
	const command = tokens[index];
	return command ? { command, args: tokens.slice(index + 1) } : undefined;
}

function isMutatingGitConfig(args: string[]): boolean {
	if (args.some((arg) => /^(?:--add|--remove-section|--rename-section|--replace-all|--unset(?:-all)?)$/.test(arg))) {
		return true;
	}
	if (args.some((arg) => ["--get", "--get-all", "--get-regexp", "--get-urlmatch", "--list", "-l"].includes(arg))) {
		return false;
	}
	return args.filter((arg) => !arg.startsWith("-")).length > 1;
}

function isGuardedTmuxCommand(arg: string): boolean {
	return GUARDED_TMUX_COMMANDS.has(arg) || arg.startsWith("kill-") || arg.startsWith("respawn-");
}

function isMutatingCurl(args: string[]): boolean {
	return args.some((arg, index) => {
		if (/^-X(?!GET$|HEAD$)/i.test(arg)) return true;
		if (/^(?:-d.+|-F.+|-T.+)$/.test(arg)) return true;
		if (/^(?:-d|--data(?:-ascii|-binary|-raw|-urlencode)?|-F|--form|-T|--upload-file)$/.test(arg)) return true;
		if (/^--(?:data|form|upload-file)=/.test(arg)) return true;
		if (arg === "-X" || arg === "--request") return !/^(?:GET|HEAD)$/i.test(args[index + 1] ?? "");
		return /^--request=(?!GET$|HEAD$)/i.test(arg);
	});
}

function isMutatingGh(args: string[]): boolean {
	const [area, action] = args;
	if (area === "api") {
		return args.some((arg, index) => {
			if (/^(?:-[fF].+|--field=|--raw-field=|--input=)/.test(arg)) return true;
			if (["-f", "-F", "--field", "--raw-field", "--input"].includes(arg)) return true;
			if (arg === "-X" || arg === "--method") return !/^(?:GET|HEAD)$/i.test(args[index + 1] ?? "");
			return /^--method=(?!GET$|HEAD$)/i.test(arg);
		});
	}
	if (area === "pr") return !["checks", "diff", "list", "status", "view"].includes(action ?? "");
	if (area === "issue") return !["list", "status", "view"].includes(action ?? "");
	if (area === "release") return !["list", "view"].includes(action ?? "");
	if (area === "auth") return action !== "status";
	return false;
}

function isHostPackageMutation(command: string, args: string[]): boolean {
	if (command === "brew") return ["cleanup", "install", "uninstall", "update", "upgrade"].includes(args[0] ?? "");
	if (["npm", "pnpm"].includes(command)) {
		const hasGlobalFlag = args.some((arg) => arg === "-g" || arg === "--global");
		return hasGlobalFlag && args.some((arg) => ["add", "i", "install", "remove", "rm", "uninstall"].includes(arg));
	}
	if (command === "yarn") return args[0] === "global";
	if (command === "gem") return ["install", "uninstall", "update"].includes(args[0] ?? "");
	if (command !== "asdf") return false;
	return (
		["install", "uninstall"].includes(args[0] ?? "") ||
		(args[0] === "plugin" && ["add", "remove"].includes(args[1] ?? ""))
	);
}

function isPublish(command: string, args: string[]): boolean {
	if (command === "npm") return ["deprecate", "publish", "unpublish"].includes(args[0] ?? "");
	return command === "gem" && ["push", "yank"].includes(args[0] ?? "");
}

function isAllowedBySessionSsh(command: string, destinations: Set<string>): boolean {
	const segments = splitShellCommand(command);
	return Boolean(segments && segments.every((segment) => isAllowedSshAccessSegment(segment, destinations)));
}

function isAllowedSshAccessSegment(segment: string, destinations: Set<string>): boolean {
	const destination = parseSshAccessSegment(segment);
	return Boolean(destination && destinations.has(destination));
}

function parseSshAccessSegment(segment: string): string | undefined {
	const tokens = tokenizeShellSegment(segment);
	if (!tokens || tokens.length < 2) return undefined;

	const command = basename(tokens[0]!);
	if (command !== "scp" && hasUnsafeShellSyntax(segment)) return undefined;
	if (command === "ssh") return simpleSshDestination(tokens[1]!);
	if (command === "sftp") return scpDestination(tokens[1]!) ?? simpleSshDestination(tokens[1]!);
	if (
		command !== "scp" ||
		hasUnsafeScpSyntax(segment) ||
		tokens.length < 3 ||
		tokens.slice(1).some((token) => token.startsWith("-"))
	) {
		return undefined;
	}

	const destinations = tokens.slice(1).map(scpDestination).filter((value) => value !== undefined);
	const destination = destinations[0];
	return destination && destinations.every((value) => value === destination) ? destination : undefined;
}

function hasUnsafeScpSyntax(segment: string): boolean {
	const sanitized = segment.replace(/"(?:\\.|[^"\\])*"/g, (quoted) =>
		quoted.replace(/\$(?:[a-z_][a-z0-9_]*|\{[a-z_][a-z0-9_]*\})/gi, "VAR"),
	);
	return hasUnsafeShellSyntax(sanitized);
}

function simpleSshDestination(value: string): string | undefined {
	return /^(?:[a-z0-9._-]+@)?(?:[a-z0-9._-]+|\[[0-9a-f:]+\])$/i.test(value) ? value : undefined;
}

function scpDestination(value: string): string | undefined {
	const match = value.match(/^((?:[a-z0-9._-]+@)?(?:[a-z0-9._-]+|\[[0-9a-f:]+\])):/i);
	return match?.[1];
}

function isAllowedBySkill(toolName: string, argValue: string, rules: string[]): boolean {
	if (toolName !== "bash") return rules.some((rule) => matchRule(rule, toolName, argValue));
	const segments = splitShellCommand(argValue);
	return Boolean(
		segments &&
			segments.every(
				(segment) => !hasUnsafeShellSyntax(segment) && rules.some((rule) => matchRule(rule, toolName, segment)),
			),
	);
}

function getMatchValue(toolName: string, input: Record<string, unknown>): string {
	if (toolName === "bash") return typeof input.command === "string" ? input.command : "";
	if (["read", "edit", "write"].includes(toolName)) return typeof input.path === "string" ? input.path : "";
	if (toolName === "fetch") return typeof input.url === "string" ? input.url : "";
	if (["grep", "find", "ls"].includes(toolName)) return typeof input.path === "string" ? input.path : "";
	return "";
}

function splitRuleString(value: string): string[] {
	const rules: string[] = [];
	let current = "";
	let depth = 0;
	for (const character of value.trim()) {
		if (/\s/.test(character) && depth === 0) {
			if (current) rules.push(current);
			current = "";
			continue;
		}
		if (character === "(") depth++;
		if (character === ")" && depth > 0) depth--;
		current += character;
	}
	if (current) rules.push(current);
	return rules;
}

function matchPattern(pattern: string, value: string): boolean {
	const wildcard = "[\\s\\S]*";
	const escaped = pattern.replace(/[.+^${}()|[\]\\]/g, "\\$&").replace(/\*/g, wildcard);
	const adjusted = escaped.endsWith(` ${wildcard}`)
		? `${escaped.slice(0, -wildcard.length - 1)}(?: ${wildcard})?`
		: escaped;
	return new RegExp(`^${adjusted}$`).test(value);
}

function pushSegment(segments: string[], value: string): void {
	if (value.trim()) segments.push(value.trim());
}

function hasUnsafeShellSyntax(segment: string): boolean {
	let quote: "'" | '"' | undefined;
	let isEscaped = false;
	for (const character of segment) {
		if (isEscaped) {
			isEscaped = false;
			continue;
		}
		if (character === "\\" && quote !== "'") {
			isEscaped = true;
			continue;
		}
		if ((character === "'" || character === '"') && (!quote || quote === character)) {
			quote = quote ? undefined : character;
			continue;
		}
		if (quote === "'") continue;
		if (character === "`" || character === "$" || character === "<" || character === ">") return true;
		if (!quote && (character === "(" || character === ")" || "*?[{".includes(character))) {
			return true;
		}
	}
	return Boolean(quote || isEscaped);
}

function tokenizeShellSegment(segment: string): string[] | undefined {
	const tokens: string[] = [];
	let current = "";
	let quote: "'" | '"' | undefined;
	let isEscaped = false;
	let hasToken = false;
	for (const character of segment) {
		if (isEscaped) {
			current += character;
			hasToken = true;
			isEscaped = false;
			continue;
		}
		if (character === "\\" && quote !== "'") {
			isEscaped = true;
			continue;
		}
		if ((character === "'" || character === '"') && (!quote || quote === character)) {
			quote = quote ? undefined : character;
			hasToken = true;
			continue;
		}
		if (!quote && /\s/.test(character)) {
			if (hasToken) tokens.push(current);
			current = "";
			hasToken = false;
			continue;
		}
		current += character;
		hasToken = true;
	}
	if (quote || isEscaped) return undefined;
	if (hasToken) tokens.push(current);
	return tokens;
}

function isPiClipboardImage(rawPath: string, cwd: string): boolean {
	const pathInfo = resolvePathInfo(rawPath, cwd);
	const tempRoot = canonicalPath(tmpdir());
	return Boolean(
		pathInfo &&
			tempRoot &&
			PI_CLIPBOARD_IMAGE.test(basename(pathInfo.lexical)) &&
			isInside(tempRoot, pathInfo.canonical),
	);
}

function resolvePathInfo(rawPath: string, cwd: string): PathInfo | undefined {
	return resolveExpandedPath(rawPath.startsWith("@") ? rawPath.slice(1) : rawPath, cwd);
}

function resolveShellPathInfo(rawPath: string, cwd: string): PathInfo | undefined {
	return resolveExpandedPath(rawPath, cwd);
}

function resolveExpandedPath(rawPath: string, cwd: string): PathInfo | undefined {
	const normalized =
		rawPath === "~" ? homedir() : rawPath.startsWith("~/") ? join(homedir(), rawPath.slice(2)) : rawPath;
	const lexical = resolve(cwd, normalized);
	const canonical = canonicalPath(lexical);
	return canonical ? { lexical, canonical } : undefined;
}

function canonicalPath(target: string, depth = 0): string | undefined {
	if (depth > 20) return undefined;
	try {
		return realpathSync(target);
	} catch (error) {
		if (!isMissingPathError(error)) return undefined;
	}
	try {
		const stat = lstatSync(target);
		if (stat.isSymbolicLink()) return canonicalPath(resolve(dirname(target), readlinkSync(target)), depth + 1);
	} catch (error) {
		if (!isMissingPathError(error)) return undefined;
	}
	const parent = dirname(target);
	if (parent === target) return target;
	const canonicalParent = canonicalPath(parent, depth + 1);
	return canonicalParent ? join(canonicalParent, basename(target)) : undefined;
}

function isMissingPathError(error: unknown): boolean {
	return error instanceof Error && "code" in error && (error as NodeJS.ErrnoException).code === "ENOENT";
}

function isGitMetadata(root: string, target: string): boolean {
	if (!isInside(root, target)) return false;
	return relative(root, target).split(sep).some((part) => part.toLowerCase() === ".git");
}

function isInside(root: string, target: string): boolean {
	const pathFromRoot = relative(root, target);
	return (
		pathFromRoot === "" ||
		(!pathFromRoot.startsWith(`..${sep}`) && pathFromRoot !== ".." && !isAbsolute(pathFromRoot))
	);
}
