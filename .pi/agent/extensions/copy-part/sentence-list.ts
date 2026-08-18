export function formatSentenceList(sentences: string[]): string {
	return sentences
		.map((sentence, index) => `${index + 1}. ${sentence.replace(/^\d+\.\s+/, "")}`)
		.join("\n");
}
