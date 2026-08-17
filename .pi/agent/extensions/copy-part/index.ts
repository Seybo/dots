import { spawn } from "node:child_process";

import type { ExtensionAPI, ExtensionCommandContext } from "@earendil-works/pi-coding-agent";
import { truncateToWidth, wrapTextWithAnsi } from "@earendil-works/pi-tui";

import { extractSentences } from "./sentences.ts";

const MAX_VISIBLE_SENTENCES = 8;

function latestAssistantText(ctx: ExtensionCommandContext): string | undefined {
	const branch = ctx.sessionManager.getBranch();

	for (let index = branch.length - 1; index >= 0; index--) {
		const entry = branch[index];
		if (entry?.type !== "message" || entry.message.role !== "assistant") continue;

		const text = entry.message.content
			.filter((block): block is { type: "text"; text: string } => block.type === "text")
			.map((block) => block.text)
			.join("\n\n");

		return text.trim() ? text : undefined;
	}

	return undefined;
}

function compactPreview(sentence: string): string {
	return sentence.replace(/\s+/g, " ").trim();
}

async function pickSentence(ctx: ExtensionCommandContext, sentences: string[]): Promise<string | null> {
	return ctx.ui.custom<string | null>((tui, theme, keybindings, done) => {
		let selectedIndex = sentences.length - 1;

		return {
			render(width: number): string[] {
				const lines = [theme.fg("accent", theme.bold("Copy sentence")), ""];
				const visibleCount = Math.min(sentences.length, MAX_VISIBLE_SENTENCES);
				const startIndex = Math.max(
					0,
					Math.min(selectedIndex - visibleCount + 1, sentences.length - visibleCount),
				);
				const endIndex = Math.min(sentences.length, startIndex + visibleCount);
				const numberWidth = String(sentences.length).length;

				for (let index = startIndex; index < endIndex; index++) {
					const prefix = index === selectedIndex ? "▶" : " ";
					const number = String(index + 1).padStart(numberWidth);
					const text = truncateToWidth(`${prefix} ${number}. ${compactPreview(sentences[index]!)}`, width, "…");
					lines.push(
						index === selectedIndex
							? theme.bg("selectedBg", theme.fg("accent", text))
							: theme.fg("dim", text),
					);
				}

				lines.push("", theme.fg("accent", `Selected sentence ${selectedIndex + 1}/${sentences.length}`));
				const previewWidth = Math.max(1, width - 2);
				const selected = theme.bg("selectedBg", theme.fg("text", sentences[selectedIndex]!));
				lines.push(...wrapTextWithAnsi(selected, previewWidth).map((line) => `  ${line}`));
				lines.push("", theme.fg("dim", "↑/↓ browse · Enter copy · Esc cancel"));

				return lines.map((line) => truncateToWidth(line, width, ""));
			},
			invalidate() {},
			handleInput(data: string) {
				if (keybindings.matches(data, "tui.select.up")) {
					selectedIndex = (selectedIndex - 1 + sentences.length) % sentences.length;
					tui.requestRender();
					return;
				}
				if (keybindings.matches(data, "tui.select.down")) {
					selectedIndex = (selectedIndex + 1) % sentences.length;
					tui.requestRender();
					return;
				}
				if (keybindings.matches(data, "tui.select.confirm")) {
					done(sentences[selectedIndex]!);
					return;
				}
				if (keybindings.matches(data, "tui.select.cancel")) done(null);
			},
		};
	});
}

function copyToClipboard(text: string): Promise<void> {
	return new Promise((resolve, reject) => {
		const child = spawn("pbcopy");
		let stderr = "";
		let isSettled = false;

		child.stderr.on("data", (chunk) => {
			stderr += String(chunk);
		});
		child.on("error", (error) => {
			if (isSettled) return;
			isSettled = true;
			reject(error);
		});
		child.on("close", (code) => {
			if (isSettled) return;
			isSettled = true;
			if (code === 0) resolve();
			else reject(new Error(stderr.trim() || `pbcopy exited with code ${code}`));
		});

		child.stdin.end(text);
	});
}

export default function copyPartExtension(pi: ExtensionAPI) {
	pi.registerCommand("cp", {
		description: "Browse and copy one sentence from the latest assistant response. Usage: /cp s",
		handler: async (args, ctx) => {
			if (args.trim() !== "s") {
				ctx.ui.notify("Usage: /cp s", "warning");
				return;
			}
			if (ctx.mode !== "tui") {
				ctx.ui.notify("/cp s requires interactive mode", "error");
				return;
			}

			const response = latestAssistantText(ctx);
			const sentences = response ? extractSentences(response) : [];
			if (sentences.length === 0) {
				ctx.ui.notify("The latest assistant response has no sentence prose to copy", "warning");
				return;
			}

			const sentence = await pickSentence(ctx, sentences);
			if (sentence === null) return;

			try {
				await copyToClipboard(sentence);
				ctx.ui.notify("Copied sentence to clipboard", "info");
			} catch (error) {
				const message = error instanceof Error ? error.message : String(error);
				ctx.ui.notify(`Failed to copy sentence: ${message}`, "error");
			}
		},
	});
}
