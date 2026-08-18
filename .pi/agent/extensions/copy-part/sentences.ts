type Fence = {
	character: "`" | "~";
	length: number;
};

function openingFence(line: string): Fence | undefined {
	const match = line.match(/^\s*(`{3,}|~{3,})/);
	const marker = match?.[1];
	if (!marker) return undefined;

	return {
		character: marker[0] as Fence["character"],
		length: marker.length,
	};
}

function isClosingFence(line: string, fence: Fence): boolean {
	const match = line.match(/^\s*(`{3,}|~{3,})\s*$/);
	const marker = match?.[1];
	return Boolean(marker && marker[0] === fence.character && marker.length >= fence.length);
}

function proseChunks(markdown: string): string[] {
	const chunks: string[] = [];
	let lines: string[] = [];
	let fence: Fence | undefined;

	const finishChunk = () => {
		const chunk = lines.join("\n");
		if (chunk.trim()) chunks.push(chunk);
		lines = [];
	};

	for (const line of markdown.split("\n")) {
		if (fence) {
			if (isClosingFence(line, fence)) fence = undefined;
			continue;
		}

		const opening = openingFence(line);
		if (opening) {
			finishChunk();
			fence = opening;
			continue;
		}

		lines.push(line);
	}

	finishChunk();
	return chunks;
}

function mergeNumberedPrefixes(sentences: string[]): string[] {
	const merged: string[] = [];

	for (let index = 0; index < sentences.length; index++) {
		const sentence = sentences[index]!;
		const next = sentences[index + 1];
		if (/^\d+\.$/.test(sentence) && next && !/^\d+\.$/.test(next)) {
			merged.push(`${sentence} ${next}`);
			index++;
		} else {
			merged.push(sentence);
		}
	}

	return merged;
}

export function extractSentences(markdown: string): string[] {
	const segmenter = new Intl.Segmenter(undefined, { granularity: "sentence" });

	return proseChunks(markdown).flatMap((chunk) => {
		const sentences = Array.from(segmenter.segment(chunk), ({ segment }) => segment.trim()).filter(Boolean);
		return mergeNumberedPrefixes(sentences);
	});
}
