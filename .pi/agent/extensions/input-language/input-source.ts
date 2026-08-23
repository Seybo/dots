const LANGUAGE_BY_INPUT_SOURCE: Readonly<Record<string, string>> = {
	ABC: "En",
	RussianWin: "Ru",
};

export function inputLanguageFromDefaults(output: string): string | undefined {
	const match = output.match(/"KeyboardLayout Name"\s*=\s*"?([^";\n]+)"?;/);
	const inputSource = match?.[1]?.trim();
	return inputSource ? LANGUAGE_BY_INPUT_SOURCE[inputSource] : undefined;
}
