// Based on Pi's official modal-editor extension example.

import { watch, type FSWatcher } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

import { CustomEditor, type ExtensionAPI, type Theme } from "@earendil-works/pi-coding-agent";
import {
	decodeKittyPrintable,
	type EditorTheme,
	type KeybindingsManager,
	matchesKey,
	sliceByColumn,
	type TUI,
	visibleWidth,
} from "@earendil-works/pi-tui";

import { inputLanguageFromDefaults } from "./input-language/input-source.ts";

// These native inputs match this environment's Pi editor keybindings.
const NORMAL_KEYS: Record<string, string> = {
	h: "\x1b[D",
	j: "\x1b[B",
	k: "\x1b[A",
	l: "\x1b[C",
	w: "\x1b[107;3u", // alt+k
	b: "\x1b[106;3u", // alt+j
	"0": "\x1b[104;3u", // alt+h
	$: "\x1b[108;3u", // alt+l
	x: "\x1b[3~",
};

const DELETE_WORD_FORWARD = "\x1b[100;3u"; // alt+d
const DELETE_TO_LINE_END = "\x1b[107;5u"; // ctrl+k
const BACKSPACE = "\x1b[127u";
const NEW_LINE = "\x1b[106;5u"; // ctrl+j
const UNDO = "\x1b[45;5u"; // ctrl+-
const INPUT_LANGUAGE_READ_TIMEOUT_MS = 1000;
const INPUT_LANGUAGE_REFRESH_DEBOUNCE_MS = 100;
const INPUT_SOURCE_PREFERENCES_DIR = join(homedir(), "Library/Preferences");
const INPUT_SOURCE_PREFERENCES_FILE = "com.apple.HIToolbox.plist";

class VimEditor extends CustomEditor {
	private mode: "normal" | "insert" = "insert";
	private pendingOperator: "d" | "c" | null = null;
	private inputLanguage: string | undefined;

	constructor(
		tui: TUI,
		editorTheme: EditorTheme,
		keybindings: KeybindingsManager,
		private readonly getTheme: () => Theme,
		private readonly requestRender: () => void,
	) {
		super(tui, editorTheme, keybindings);
	}

	setInputLanguage(language: string | undefined): void {
		if (language === this.inputLanguage) return;

		this.inputLanguage = language;
		this.requestRender();
	}

	handleInput(data: string): void {
		if (matchesKey(data, "escape")) {
			if (this.mode === "insert") {
				if (this.isShowingAutocomplete()) {
					super.handleInput(data);
				} else {
					this.mode = "normal";
				}
			} else {
				this.pendingOperator = null;
				super.handleInput(data);
			}
			return;
		}

		if (this.mode === "insert") {
			super.handleInput(data);
			return;
		}

		if (matchesKey(data, "enter")) {
			this.pendingOperator = null;
			this.mode = "insert";
			super.handleInput(data);
			return;
		}

		const printable = decodeKittyPrintable(data);
		const key = printable ?? data;
		const isPrintable =
			printable !== undefined ||
			(data.length > 0 &&
				[...data].every((character) => {
					const codePoint = character.codePointAt(0) ?? 0;
					return codePoint >= 32 && codePoint !== 127;
				}));

		if (this.pendingOperator) {
			const operator = this.pendingOperator;
			this.pendingOperator = null;

			if (key === "w") {
				super.handleInput(DELETE_WORD_FORWARD);
				if (operator === "c") this.mode = "insert";
				return;
			}

			if (key === "d" && operator === "d") {
				this.deleteCurrentLine();
				return;
			}

			if (key === "$") {
				this.applyLineEndOperator(operator === "c");
				return;
			}

			if (!isPrintable) super.handleInput(data);
			return;
		}

		if (key === "d" || key === "c") {
			this.pendingOperator = key;
			return;
		}

		if (key === "D" || key === "C") {
			this.applyLineEndOperator(key === "C");
			return;
		}

		if (key === "i") {
			this.mode = "insert";
			return;
		}

		if (key === "I") {
			super.handleInput(NORMAL_KEYS["0"]);
			this.mode = "insert";
			return;
		}

		if (key === "o" || key === "O") {
			super.handleInput(key === "o" ? NORMAL_KEYS.$ : NORMAL_KEYS["0"]);
			super.handleInput(NEW_LINE);
			if (key === "O") super.handleInput(NORMAL_KEYS.k);
			this.mode = "insert";
			return;
		}

		if (key === "u") {
			super.handleInput(UNDO);
			return;
		}

		if (key === "a") {
			super.handleInput(NORMAL_KEYS.l);
			this.mode = "insert";
			return;
		}

		if (key === "A") {
			super.handleInput(NORMAL_KEYS.$);
			this.mode = "insert";
			return;
		}

		const mappedInput = NORMAL_KEYS[key];
		if (mappedInput) {
			super.handleInput(mappedInput);
			return;
		}

		if (isPrintable) return;
		super.handleInput(data);
	}

	private applyLineEndOperator(isChange: boolean): void {
		const { line, col } = this.getCursor();
		if (col < (this.getLines()[line]?.length ?? 0)) {
			super.handleInput(DELETE_TO_LINE_END);
		}
		if (isChange) this.mode = "insert";
	}

	private deleteCurrentLine(): void {
		const { line } = this.getCursor();
		const lines = this.getLines();
		super.handleInput(NORMAL_KEYS["0"]);

		if (lines[line]?.length) super.handleInput(DELETE_TO_LINE_END);

		if (line < lines.length - 1) {
			super.handleInput(DELETE_TO_LINE_END);
		} else if (line > 0) {
			super.handleInput(BACKSPACE);
		}
	}

	private applyNormalBackground(line: string, width: number, theme: Theme): string {
		const paddedLine = line + " ".repeat(Math.max(0, width - visibleWidth(line)));
		return paddedLine
			.split("\x1b[0m")
			.map((segment) => theme.bg("selectedBg", segment))
			.join("\x1b[0m");
	}

	render(width: number): string[] {
		const lines = super.render(width);
		if (lines.length === 0) return lines;

		const theme = this.getTheme();
		const plainLanguageLabel = this.inputLanguage ? `  ${this.inputLanguage} ` : "";
		const languageLabel =
			this.inputLanguage === "Ru"
				? theme.inverse(theme.fg("error", plainLanguageLabel))
				: plainLanguageLabel;
		const modeLabel = this.mode === "normal" ? "  NORMAL " : "  INSERT ";
		const label = languageLabel + modeLabel;
		const labelWidth = visibleWidth(label);
		const last = lines.length - 1;
		const lastWidth = visibleWidth(lines[last]!);
		if (lastWidth >= labelWidth) {
			lines[last] = sliceByColumn(lines[last]!, 0, lastWidth - labelWidth) + label;
		}

		if (this.mode === "normal") {
			for (let index = 1; index < last; index++) {
				lines[index] = this.applyNormalBackground(lines[index]!, width, theme);
			}
		}
		return lines;
	}
}

export default function (pi: ExtensionAPI) {
	let activeEditor: VimEditor | undefined;
	let inputLanguage: string | undefined;
	let isInputLanguageRefreshRunning = false;
	let inputSourceWatcher: FSWatcher | undefined;
	let refreshTimer: ReturnType<typeof setTimeout> | undefined;

	async function refreshInputLanguage(): Promise<void> {
		if (isInputLanguageRefreshRunning) return;

		isInputLanguageRefreshRunning = true;
		try {
			const result = await pi.exec(
				"defaults",
				["read", "com.apple.HIToolbox", "AppleSelectedInputSources"],
				{ timeout: INPUT_LANGUAGE_READ_TIMEOUT_MS },
			);
			inputLanguage = inputLanguageFromDefaults(result.stdout);
			activeEditor?.setInputLanguage(inputLanguage);
		} catch {
			return;
		} finally {
			isInputLanguageRefreshRunning = false;
		}
	}

	function scheduleInputLanguageRefresh(): void {
		if (refreshTimer) clearTimeout(refreshTimer);
		refreshTimer = setTimeout(() => {
			refreshTimer = undefined;
			void refreshInputLanguage();
		}, INPUT_LANGUAGE_REFRESH_DEBOUNCE_MS);
	}

	// Watch the directory because cfprefsd may replace the plist rather than update its inode.
	// The old one-second poll spawned `defaults` from every Pi session, multiplying
	// macOS policy validations and driving high syspolicyd CPU usage.
	function startInputSourceWatcher(): void {
		if (inputSourceWatcher) return;

		inputSourceWatcher = watch(
			INPUT_SOURCE_PREFERENCES_DIR,
			{ persistent: false },
			(_eventType, filename) => {
				if (filename && filename.toString() !== INPUT_SOURCE_PREFERENCES_FILE) return;
				scheduleInputLanguageRefresh();
			},
		);
	}

	pi.on("session_start", (_event, ctx) => {
		const isInputLanguageEnabled = process.env.MACHINE_NAME === "squirrel" && ctx.mode === "tui";
		ctx.ui.setEditorComponent((tui, theme, keybindings) => {
			const editor = new VimEditor(
				tui,
				theme,
				keybindings,
				() => ctx.ui.theme,
				() => tui.requestRender(),
			);

			if (isInputLanguageEnabled) {
				activeEditor = editor;
				editor.setInputLanguage(inputLanguage);
			}

			return editor;
		});

		if (isInputLanguageEnabled) {
			startInputSourceWatcher();
			void refreshInputLanguage();
		}
	});

	pi.on("session_shutdown", () => {
		inputSourceWatcher?.close();
		if (refreshTimer) clearTimeout(refreshTimer);
		activeEditor = undefined;
		inputLanguage = undefined;
		isInputLanguageRefreshRunning = false;
		inputSourceWatcher = undefined;
		refreshTimer = undefined;
	});
}
