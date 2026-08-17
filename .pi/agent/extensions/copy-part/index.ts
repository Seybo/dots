import { spawn } from "node:child_process";

import type { ExtensionAPI, ExtensionCommandContext } from "@earendil-works/pi-coding-agent";
import { truncateToWidth, wrapTextWithAnsi } from "@earendil-works/pi-tui";

import { extractCodeBlocks } from "./code-blocks.ts";
import { extractSentences } from "./sentences.ts";

const MAX_VISIBLE_ITEMS = 8;

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

function compactPreview(item: string): string {
	return item.replace(/\s+/g, " ").trim();
}

async function pickPart(
	ctx: ExtensionCommandContext,
	items: string[],
	partName: "sentence" | "code block",
): Promise<string | null> {
	return ctx.ui.custom<string | null>((tui, theme, keybindings, done) => {
		let selectedIndex = items.length - 1;

		return {
			render(width: number): string[] {
				const lines = [theme.fg("accent", theme.bold(`Copy ${partName}`)), ""];
				const visibleCount = Math.min(items.length, MAX_VISIBLE_ITEMS);
				const startIndex = Math.max(
					0,
					Math.min(selectedIndex - visibleCount + 1, items.length - visibleCount),
				);
				const endIndex = Math.min(items.length, startIndex + visibleCount);
				const numberWidth = String(items.length).length;

				for (let index = startIndex; index < endIndex; index++) {
					const prefix = index === selectedIndex ? "▶" : " ";
					const number = String(index + 1).padStart(numberWidth);
					const text = truncateToWidth(`${prefix} ${number}. ${compactPreview(items[index]!)}`, width, "…");
					lines.push(
						index === selectedIndex
							? theme.bg("selectedBg", theme.fg("accent", text))
							: theme.fg("dim", text),
					);
				}

				lines.push("", theme.fg("accent", `Selected ${partName} ${selectedIndex + 1}/${items.length}`));
				const previewWidth = Math.max(1, width - 2);
				const selected = theme.bg("selectedBg", theme.fg("text", items[selectedIndex]!));
				lines.push(...wrapTextWithAnsi(selected, previewWidth).map((line) => `  ${line}`));
				lines.push("", theme.fg("dim", "↑/↓ browse · Enter copy · Esc cancel"));

				return lines.map((line) => truncateToWidth(line, width, ""));
			},
			invalidate() {},
			handleInput(data: string) {
				if (keybindings.matches(data, "tui.select.up")) {
					selectedIndex = (selectedIndex - 1 + items.length) % items.length;
					tui.requestRender();
					return;
				}
				if (keybindings.matches(data, "tui.select.down")) {
					selectedIndex = (selectedIndex + 1) % items.length;
					tui.requestRender();
					return;
				}
				if (keybindings.matches(data, "tui.select.confirm")) {
					done(items[selectedIndex]!);
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
		description: "Browse and copy one sentence or code block from the latest assistant response",
		handler: async (args, ctx) => {
			const mode = args.trim();
			if (mode !== "s" && mode !== "c") {
				ctx.ui.notify("Usage: /cp s or /cp c", "warning");
				return;
			}
			if (ctx.mode !== "tui") {
				ctx.ui.notify(`/cp ${mode} requires interactive mode`, "error");
				return;
			}

			const response = latestAssistantText(ctx);
			const partName = mode === "s" ? "sentence" : "code block";
			const items = response
				? mode === "s"
					? extractSentences(response)
					: extractCodeBlocks(response)
				: [];
			if (items.length === 0) {
				const missing = mode === "s" ? "sentence prose" : "fenced code block";
				ctx.ui.notify(`The latest assistant response has no ${missing} to copy`, "warning");
				return;
			}

			const item = await pickPart(ctx, items, partName);
			if (item === null) return;

			try {
				await copyToClipboard(item);
				ctx.ui.notify(`Copied ${partName} to clipboard`, "info");
			} catch (error) {
				const message = error instanceof Error ? error.message : String(error);
				ctx.ui.notify(`Failed to copy ${partName}: ${message}`, "error");
			}
		},
	});
}
