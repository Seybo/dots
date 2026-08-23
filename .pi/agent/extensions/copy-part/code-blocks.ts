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

function inlineCode(line: string): string[] {
	return Array.from(line.matchAll(/`([^`\n]+)`/g), (match) => match[1]!).filter((body) =>
		body.trim(),
	);
}

export function extractCodeParts(markdown: string): string[] {
	const parts: string[] = [];
	let fence: Fence | undefined;
	let lines: string[] = [];

	for (const line of markdown.split("\n")) {
		if (!fence) {
			const opening = openingFence(line);
			if (opening) {
				fence = opening;
				lines = [];
			} else {
				parts.push(...inlineCode(line));
			}
			continue;
		}

		if (isClosingFence(line, fence)) {
			const body = lines.join("\n");
			if (body.trim()) parts.push(body);
			fence = undefined;
			lines = [];
			continue;
		}

		lines.push(line);
	}

	return parts;
}
