import { existsSync, lstatSync, readlinkSync, realpathSync } from "node:fs";
import { homedir, tmpdir } from "node:os";
import { basename, dirname, isAbsolute, join, relative, resolve, sep } from "node:path";

export type PermissionMode = "repository" | "ask" | "unrestricted";

export type PermissionDecision =
	| { kind: "allow" }
	| { kind: "ask"; reason: string }
	| { kind: "suggest"; tool: "read" | "edit" | "write"; reason: string };

export type RepositoryState = {
	root: string;
	protectedPaths: Set<string>;
};

type ToolCall = {
	mode: PermissionMode;
	toolName: string;
	input: Record<string, unknown>;
	cwd: string;
	repository?: RepositoryState;
	skillRules: string[];
};

type PathInfo = {
	lexical: string;
	canonical: string;
};

const ALLOW: PermissionDecision = { kind: "allow" };
const PATH_TOOLS = new Set(["read", "edit", "write"]);
const PI_CLIPBOARD_IMAGE = /^pi-clipboard-[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\.png$/i;
const READ_ONLY_COMMANDS = new Set(["pwd", "ls", "rg", "grep", "head", "tail", "wc", "nl", "sort", "test", "cmp"]);
const READ_ONLY_GIT_COMMANDS = new Set([
	"status",
	"diff",
	"log",
	"show",
	"rev-parse",
	"merge-base",
	"rev-list",
	"ls-files",
	"ls-tree",
	"cat-file",
	"for-each-ref",
	"show-ref",
	"blame",
	"grep",
	"describe",
	"shortlog",
	"count-objects",
]);

export function parseProtectedPaths(root: string, output: string): Set<string> {
	return new Set(
		output
			.split("\0")
			.filter(Boolean)
			.map((entry) => resolve(root, entry)),
	);
}

export function parseRuleList(value: unknown): string[] {
	const entries = Array.isArray(value) ? value : typeof value === "string" ? [value] : [];
	return entries
		.filter((entry): entry is string => typeof entry === "string")
		.flatMap(splitRuleString);
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
			if (current.trim()) segments.push(current.trim());
			current = "";
			index++;
			continue;
		}
		if (character === "|" || character === ";") {
			if (current.trim()) segments.push(current.trim());
			current = "";
			continue;
		}

		current += character;
	}

	if (quote || isEscaped) return undefined;
	if (current.trim()) segments.push(current.trim());
	return segments.length > 0 ? segments : undefined;
}

export function decideToolCall(call: ToolCall): PermissionDecision {
	if (call.mode === "unrestricted") return ALLOW;

	const argValue = getMatchValue(call.toolName, call.input);
	if (call.toolName === "read" && argValue && isPiClipboardImage(argValue, call.cwd)) return ALLOW;
	if ((call.toolName === "edit" || call.toolName === "write") && call.repository && argValue) {
		const pathDecision = decidePathTool(call.toolName, argValue, call.cwd, call.repository);
		if (pathDecision.kind === "ask" && /protected/i.test(pathDecision.reason)) return pathDecision;
	}

	if (call.mode === "ask") {
		return isAllowedBySkill(call.toolName, argValue, call.skillRules)
			? ALLOW
			: { kind: "ask", reason: "Ask mode requires approval." };
	}

	if (!call.repository) {
		return { kind: "ask", reason: "Repository mode is unavailable." };
	}

	if (PATH_TOOLS.has(call.toolName)) {
		if (isAllowedBySkill(call.toolName, argValue, call.skillRules)) return ALLOW;
		if (!argValue) return { kind: "ask", reason: `${call.toolName} has no path to validate.` };
		return decidePathTool(call.toolName, argValue, call.cwd, call.repository);
	}

	if (call.toolName === "bash") {
		if (!argValue) return { kind: "ask", reason: "Bash has no command to validate." };
		return decideBash(argValue, call.cwd, call.repository, call.skillRules);
	}

	return isAllowedBySkill(call.toolName, argValue, call.skillRules)
		? ALLOW
		: { kind: "ask", reason: `${call.toolName} is not repository-aware.` };
}

function decidePathTool(
	toolName: string,
	rawPath: string,
	cwd: string,
	repository: RepositoryState,
): PermissionDecision {
	const pathInfo = resolvePathInfo(rawPath, cwd);
	if (!pathInfo) return { kind: "ask", reason: `Could not resolve ${rawPath} safely.` };

	const canonicalRoot = canonicalPath(repository.root);
	const isMutation = toolName === "edit" || toolName === "write";
	if (
		isMutation &&
		(repository.protectedPaths.has(pathInfo.lexical) || repository.protectedPaths.has(pathInfo.canonical))
	) {
		return { kind: "ask", reason: `${rawPath} was protected when Repository mode started.` };
	}
	if (
		isMutation &&
		canonicalRoot &&
		(isGitMetadata(canonicalRoot, pathInfo.lexical) || isGitMetadata(canonicalRoot, pathInfo.canonical))
	) {
		return { kind: "ask", reason: `${rawPath} is protected Git metadata.` };
	}

	if (!canonicalRoot || !isInside(canonicalRoot, pathInfo.canonical)) {
		return { kind: "ask", reason: `${rawPath} resolves outside the repository.` };
	}

	return ALLOW;
}

function decideBash(
	command: string,
	cwd: string,
	repository: RepositoryState,
	skillRules: string[],
): PermissionDecision {
	const segments = splitShellCommand(command);
	if (!segments || /[\r\n]/.test(command)) {
		return { kind: "ask", reason: "The shell command shape cannot be validated." };
	}

	for (const segment of segments) {
		if (isAllowedBySkill("bash", segment, skillRules)) continue;

		const suggestion = suggestedAlternative(segment);
		if (suggestion) return suggestion;

		const decision = decideReadOnlySegment(segment, cwd, repository.root);
		if (decision.kind !== "allow") return decision;
	}

	return ALLOW;
}

function decideReadOnlySegment(segment: string, cwd: string, root: string): PermissionDecision {
	if (hasUnsafeShellSyntax(segment)) {
		return { kind: "ask", reason: "Shell expansion or redirection requires approval." };
	}

	const tokens = tokenizeShellSegment(segment);
	if (!tokens || tokens.length === 0) {
		return { kind: "ask", reason: "The shell command cannot be tokenized safely." };
	}

	const command = tokens[0]!;
	if (command === "git") {
		if (!isReadOnlyGit(tokens, cwd, root)) {
			return { kind: "ask", reason: "The Git command is not a recognized read-only shape." };
		}
	} else {
		if (!READ_ONLY_COMMANDS.has(command) || hasRiskyFlags(command, tokens.slice(1))) {
			return { kind: "ask", reason: `${command} is not a recognized read-only command shape.` };
		}
		if (!tokensStayInside(tokens.slice(1), cwd, root)) {
			return { kind: "ask", reason: "A command path resolves outside the repository." };
		}
	}

	return ALLOW;
}

function suggestedAlternative(segment: string): PermissionDecision | undefined {
	if (/^cat(?:\s|$)/.test(segment)) {
		return { kind: "suggest", tool: "read", reason: "Use read for file content." };
	}
	if (/^(?:sed\b[^\n]*\s(?:-i|--in-place)|perl\b[^\n]*\s-(?:pi|ip)\b)/.test(segment)) {
		return { kind: "suggest", tool: "edit", reason: "Use edit for deterministic file changes." };
	}
	if (/^(?:printf|echo)\b[^\n]*(?:>|>>)/.test(segment)) {
		return { kind: "suggest", tool: "write", reason: "Use write for complete file content." };
	}
	return undefined;
}

function hasRiskyFlags(command: string, args: string[]): boolean {
	const flags = new Set(args);
	if (
		command === "rg" &&
		(args.some(
			(arg) =>
				arg === "--pre" ||
				arg.startsWith("--pre=") ||
				arg === "--hostname-bin" ||
				arg.startsWith("--hostname-bin="),
		) ||
			hasShortFlag(args, "L") ||
			flags.has("--follow"))
	) {
		return true;
	}
	if (command === "grep" && (hasShortFlag(args, "R") || flags.has("--dereference-recursive"))) {
		return true;
	}
	if (
		command === "ls" &&
		(hasShortFlag(args, "R") || flags.has("--recursive")) &&
		(hasShortFlag(args, "L") || flags.has("--dereference"))
	) {
		return true;
	}
	if (
		command === "sort" &&
		args.some((arg) => arg === "-o" || (arg.startsWith("-o") && arg.length > 2) || arg === "--output" || arg.startsWith("--output="))
	) {
		return true;
	}
	if (command === "sort" && args.some((arg) => arg === "--compress-program" || arg.startsWith("--compress-program="))) {
		return true;
	}
	return flags.has("--files-from") && command === "rg";
}

function hasShortFlag(args: string[], flag: string): boolean {
	return args.some((arg) => arg.startsWith("-") && !arg.startsWith("--") && arg.slice(1).includes(flag));
}

function isReadOnlyGit(tokens: string[], cwd: string, root: string): boolean {
	let index = 1;
	let gitCwd = cwd;
	while (index < tokens.length && tokens[index]!.startsWith("-")) {
		const option = tokens[index]!;
		if (option === "-C") {
			const target = tokens[index + 1];
			const targetInfo = target ? resolvePathInfo(target, gitCwd) : undefined;
			const canonicalRoot = canonicalPath(root);
			if (!targetInfo || !canonicalRoot || !isInside(canonicalRoot, targetInfo.canonical)) return false;
			gitCwd = targetInfo.canonical;
			index += 2;
			continue;
		}
		if (["--no-pager", "--no-optional-locks", "--literal-pathspecs", "--no-replace-objects"].includes(option)) {
			index++;
			continue;
		}
		return false;
	}

	const subcommand = tokens[index];
	if (!subcommand) return false;
	const args = tokens.slice(index + 1);

	if (subcommand === "branch") {
		if (args.some(isMutatingBranchArgument)) return false;
		return args.length === 0 || ["--show-current", "--list", "-a", "-r", "-v", "-vv"].includes(args[0]!);
	}
	if (subcommand === "reflog") return args.length === 0 || args[0] === "show";
	if (subcommand === "stash") return args[0] === "list";
	if (subcommand === "tag") return args[0] === "--list" || args[0] === "-l";
	if (subcommand === "worktree") return args[0] === "list";
	if (subcommand === "submodule") return args[0] === "status";
	if (!READ_ONLY_GIT_COMMANDS.has(subcommand)) return false;

	if (
		args.some(
			(arg) =>
				arg === "--output" ||
				arg.startsWith("--output=") ||
				arg === "--ext-diff" ||
				arg === "--textconv" ||
				arg === "--filters" ||
				arg === "--open-files-in-pager" ||
				arg.startsWith("--open-files-in-pager="),
		)
	) {
		return false;
	}

	return tokensStayInside(args, gitCwd, root);
}

function isMutatingBranchArgument(arg: string): boolean {
	return (
		["-d", "-D", "-m", "-M", "-c", "-C", "-f", "-t", "-u"].includes(arg) ||
		["--delete", "--move", "--copy", "--force", "--track", "--unset-upstream", "--edit-description", "--create-reflog"].includes(arg) ||
		arg.startsWith("--track=") ||
		arg === "--set-upstream-to" ||
		arg.startsWith("--set-upstream-to=")
	);
}

function tokensStayInside(tokens: string[], cwd: string, root: string): boolean {
	for (const token of tokens) {
		if (token.startsWith("~")) return false;
		if (token.startsWith("-") && token.includes("/") && !token.includes("=")) return false;

		const value = token.startsWith("-") && token.includes("=") ? token.slice(token.indexOf("=") + 1) : token;
		if (!looksLikePath(value, cwd)) continue;
		if (!pathStaysInside(value, cwd, root)) return false;
	}
	return true;
}

function looksLikePath(value: string, cwd: string): boolean {
	return (
		isAbsolute(value) ||
		value.startsWith(".") ||
		value.includes("/") ||
		existsSync(resolve(cwd, value))
	);
}

function pathStaysInside(value: string, cwd: string, root: string): boolean {
	const info = resolvePathInfo(value, cwd);
	const canonicalRoot = canonicalPath(root);
	return Boolean(info && canonicalRoot && isInside(canonicalRoot, info.canonical));
}

function isAllowedBySkill(toolName: string, argValue: string, rules: string[]): boolean {
	if (toolName !== "bash") return rules.some((rule) => matchRule(rule, toolName, argValue));
	if (/[\r\n]/.test(argValue)) return false;

	const segments = splitShellCommand(argValue);
	return Boolean(
		segments &&
			segments.every(
				(segment) =>
					!hasUnsafeShellSyntax(segment) && rules.some((rule) => matchRule(rule, toolName, segment)),
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

function hasUnsafeShellSyntax(segment: string): boolean {
	let quote: "'" | '"' | undefined;
	let isEscaped = false;

	for (let index = 0; index < segment.length; index++) {
		const character = segment[index]!;
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
		if (!quote && (character === "(" || character === ")" || character === "&" || "*?[{}".includes(character))) {
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
	const withoutAt = rawPath.startsWith("@") ? rawPath.slice(1) : rawPath;
	const normalized = withoutAt === "~" ? homedir() : withoutAt.startsWith("~/") ? join(homedir(), withoutAt.slice(2)) : withoutAt;
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
		if (stat.isSymbolicLink()) {
			const linkTarget = readlinkSync(target);
			return canonicalPath(resolve(dirname(target), linkTarget), depth + 1);
		}
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
	return pathFromRoot === "" || (!pathFromRoot.startsWith(`..${sep}`) && pathFromRoot !== ".." && !isAbsolute(pathFromRoot));
}
