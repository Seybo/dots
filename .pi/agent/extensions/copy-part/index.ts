import { spawn } from "node:child_process";

import type { ExtensionAPI, ExtensionCommandContext } from "@earendil-works/pi-coding-agent";
import { Key, matchesKey, truncateToWidth, wrapTextWithAnsi } from "@earendil-works/pi-tui";

import { extractCodeBlocks } from "./code-blocks.ts";
import { extractFilePaths } from "./file-paths.ts";
import { extractLinks } from "./links.ts";
import { PickerState } from "./picker-state.ts";
import { formatSentenceList } from "./sentence-list.ts";
import { parseCopyArgs, resolveSelection } from "./selection.ts";
import { extractSentences } from "./sentences.ts";

const MAX_VISIBLE_ITEMS = 8;

type ModeConfig = {
	partName: "sentence" | "code block" | "link" | "file path";
	missing: string;
	extract: (response: string) => string[];
	isMultiSelect?: boolean;
};

const MODES = {
	s: {
		partName: "sentence",
		missing: "sentence prose",
		extract: extractSentences,
		isMultiSelect: true,
	},
	c: { partName: "code block", missing: "fenced code block", extract: extractCodeBlocks },
	l: { partName: "link", missing: "web link", extract: extractLinks },
	f: { partName: "file path", missing: "file path", extract: extractFilePaths },
} satisfies Record<string, ModeConfig>;

type Mode = keyof typeof MODES;

function isMode(mode: string): mode is Mode {
	return Object.hasOwn(MODES, mode);
}

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
	partName: ModeConfig["partName"],
	isMultiSelect: boolean,
): Promise<string | null> {
	return ctx.ui.custom<string | null>((tui, theme, keybindings, done) => {
		const state = new PickerState(items.length);

		return {
			render(width: number): string[] {
				const lines = [theme.fg("accent", theme.bold(`Copy ${partName}`)), ""];
				const visibleCount = Math.min(items.length, MAX_VISIBLE_ITEMS);
				const startIndex = Math.max(
					0,
					Math.min(state.selectedIndex - visibleCount + 1, items.length - visibleCount),
				);
				const endIndex = Math.min(items.length, startIndex + visibleCount);
				const numberWidth = String(items.length).length;

				for (let index = startIndex; index < endIndex; index++) {
					const prefix = index === state.selectedIndex ? "▶" : " ";
					const mark = isMultiSelect ? `${state.isMarked(index) ? "[x]" : "[ ]"} ` : "";
					const number = String(index + 1).padStart(numberWidth);
					const text = truncateToWidth(
						`${prefix} ${mark}${number}. ${compactPreview(items[index]!)}`,
						width,
						"…",
					);
					lines.push(
						index === state.selectedIndex
							? theme.bg("selectedBg", theme.fg("accent", text))
							: theme.fg("dim", text),
					);
				}

				const marked = isMultiSelect ? ` · Marked ${state.markedIndexes.size}` : "";
				lines.push(
					"",
					theme.fg(
						"accent",
						`Selected ${partName} ${state.selectedIndex + 1}/${items.length}${marked}`,
					),
				);
				const previewWidth = Math.max(1, width - 2);
				const selected = theme.bg("selectedBg", theme.fg("text", items[state.selectedIndex]!));
				lines.push(...wrapTextWithAnsi(selected, previewWidth).map((line) => `  ${line}`));
				const help = isMultiSelect
					? "↑/↓/j/k browse · Space mark · Enter copy · Esc cancel"
					: "↑/↓/j/k browse · Enter copy · Esc cancel";
				lines.push("", theme.fg("dim", help));

				return lines.map((line) => truncateToWidth(line, width, ""));
			},
			invalidate() {},
			handleInput(data: string) {
				if (keybindings.matches(data, "tui.select.up") || data === "k") {
					state.move(-1);
					tui.requestRender();
					return;
				}
				if (keybindings.matches(data, "tui.select.down") || data === "j") {
					state.move(1);
					tui.requestRender();
					return;
				}
				if (isMultiSelect && matchesKey(data, Key.space)) {
					state.toggleMark();
					state.moveNext();
					tui.requestRender();
					return;
				}
				if (keybindings.matches(data, "tui.select.confirm")) {
					const chosen = state.chosenItems(items);
					const result =
						isMultiSelect && state.markedIndexes.size > 0
							? formatSentenceList(chosen)
							: chosen[0]!;
					done(result);
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
		description: "Browse and copy one sentence, code block, web link, or file path from the latest assistant response",
		handler: async (args, ctx) => {
			const parsed = parseCopyArgs(args);
			if (!parsed || !isMode(parsed.mode)) {
				ctx.ui.notify("Usage: /cp <s|c|l|f> [number|l]", "warning");
				return;
			}
			if (ctx.mode !== "tui") {
				ctx.ui.notify(`/cp ${parsed.mode} requires interactive mode`, "error");
				return;
			}

			const config = MODES[parsed.mode];
			const response = latestAssistantText(ctx);
			const items = response ? config.extract(response) : [];
			if (items.length === 0) {
				ctx.ui.notify(`The latest assistant response has no ${config.missing} to copy`, "warning");
				return;
			}

			const selection = resolveSelection(items, parsed.selector);
			if (selection.kind === "invalid") {
				ctx.ui.notify(`No ${config.partName} matches selector ${parsed.selector}`, "warning");
				return;
			}

			const item =
				selection.kind === "picker"
					? await pickPart(ctx, items, config.partName, config.isMultiSelect ?? false)
					: selection.item;
			if (item === null) return;

			try {
				await copyToClipboard(item);
				ctx.ui.notify(`Copied ${config.partName} to clipboard`, "info");
			} catch (error) {
				const message = error instanceof Error ? error.message : String(error);
				ctx.ui.notify(`Failed to copy ${config.partName}: ${message}`, "error");
			}
		},
	});
}
