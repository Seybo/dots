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

export function extractCodeBlocks(markdown: string): string[] {
	const blocks: string[] = [];
	let fence: Fence | undefined;
	let lines: string[] = [];

	for (const line of markdown.split("\n")) {
		if (!fence) {
			fence = openingFence(line);
			lines = [];
			continue;
		}

		if (isClosingFence(line, fence)) {
			const body = lines.join("\n");
			if (body.trim()) blocks.push(body);
			fence = undefined;
			lines = [];
			continue;
		}

		lines.push(line);
	}

	return blocks;
}
