// Based on Pi's official modal-editor extension example.

import { CustomEditor, type ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { decodeKittyPrintable, matchesKey, truncateToWidth, visibleWidth } from "@earendil-works/pi-tui";

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

class VimEditor extends CustomEditor {
	private mode: "normal" | "insert" = "insert";
	private pendingOperator: "d" | "c" | null = null;

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

	render(width: number): string[] {
		const lines = super.render(width);
		if (lines.length === 0) return lines;

		const label = this.mode === "normal" ? " NORMAL " : " INSERT ";
		const last = lines.length - 1;
		if (visibleWidth(lines[last]!) >= label.length) {
			lines[last] = truncateToWidth(lines[last]!, width - label.length, "") + label;
		}
		return lines;
	}
}

export default function (pi: ExtensionAPI) {
	pi.on("session_start", (_event, ctx) => {
		ctx.ui.setEditorComponent((tui, theme, keybindings) => new VimEditor(tui, theme, keybindings));
	});
}
