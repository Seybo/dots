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

const URL_PATTERN = /https?:\/\/[^\s<>()\[\]{}"']+/g;
const REFERENCE_DEFINITION = /^\s{0,3}\[[^\]]+\]:/;

export function extractLinks(markdown: string): string[] {
	const links: string[] = [];
	let fence: Fence | undefined;

	for (const line of markdown.split("\n")) {
		if (fence) {
			if (isClosingFence(line, fence)) fence = undefined;
			continue;
		}

		fence = openingFence(line);
		if (fence || REFERENCE_DEFINITION.test(line)) continue;

		links.push(...(line.match(URL_PATTERN) ?? []));
	}

	return links;
}
