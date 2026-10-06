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

function quoteBody(line: string): string | undefined {
	return line.match(/^ {0,3}> ?(.*)$/)?.[1];
}

export function extractQuotes(markdown: string): string[] {
	const quotes: string[] = [];
	let lines: string[] = [];
	let fence: Fence | undefined;

	const finishQuote = () => {
		const quote = lines.join("\n");
		if (quote.trim()) quotes.push(quote);
		lines = [];
	};

	for (const line of markdown.split("\n")) {
		if (fence) {
			if (isClosingFence(line, fence)) fence = undefined;
			continue;
		}

		const opening = openingFence(line);
		if (opening) {
			finishQuote();
			fence = opening;
			continue;
		}

		const body = quoteBody(line);
		if (body !== undefined) lines.push(body);
		else finishQuote();
	}

	finishQuote();
	return quotes;
}
