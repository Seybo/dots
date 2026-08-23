type Fence = {
	character: "`" | "~";
	length: number;
};

function openingFence(line: string): Fence | undefined {
	const marker = line.match(/^\s*(`{3,}|~{3,})/)?.[1];
	if (!marker) return undefined;

	return {
		character: marker[0] as Fence["character"],
		length: marker.length,
	};
}

function isClosingFence(line: string, fence: Fence): boolean {
	const marker = line.match(/^\s*(`{3,}|~{3,})\s*$/)?.[1];
	return Boolean(marker && marker[0] === fence.character && marker.length >= fence.length);
}

const CANDIDATE_PATTERN =
	/\[[^\]\n]*\]\((?<markdown>[^)\s]+)\)|`(?<inline>[^`\n]+)`|(?<url>https?:\/\/[^\s<>()\[\]{}"']+)|(?<bare>[^\s<>()\[\]{}"'`]+)/g;
const PATH_PATTERN = /^(?<path>[A-Za-z0-9._@+%~/-]+?)(?::\d+(?::\d+)?)?$/;

function normalizePath(candidate: string): string | undefined {
	const value = candidate.replace(/[.,;:!?]+$/, "");
	const path = value.match(PATH_PATTERN)?.groups?.path;
	if (!path || !path.includes("/") || path.includes("//") || path.endsWith("/")) return undefined;

	if (path.startsWith("~/")) return value;
	if (path.includes("~")) return undefined;
	if (path.startsWith("/")) {
		const remainder = path.slice(1);
		return remainder.includes("/") || remainder.includes(".") ? value : undefined;
	}
	if (path.startsWith("./") || path.startsWith("../")) return value;

	const filename = path.slice(path.lastIndexOf("/") + 1);
	return filename.includes(".") ? value : undefined;
}

export function extractFilePaths(markdown: string): string[] {
	const paths: string[] = [];
	let fence: Fence | undefined;

	for (const line of markdown.split("\n")) {
		if (fence) {
			if (isClosingFence(line, fence)) fence = undefined;
			continue;
		}

		fence = openingFence(line);
		if (fence) continue;

		for (const match of line.matchAll(CANDIDATE_PATTERN)) {
			if (match.groups?.url) continue;

			const candidate = match.groups?.markdown ?? match.groups?.inline ?? match.groups?.bare;
			if (!candidate) continue;

			const path = normalizePath(candidate);
			if (path) paths.push(path);
		}
	}

	return paths;
}
