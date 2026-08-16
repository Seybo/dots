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

class VimEditor extends CustomEditor {
	private mode: "normal" | "insert" = "insert";

	handleInput(data: string): void {
		if (matchesKey(data, "escape")) {
			if (this.mode === "insert") {
				if (this.isShowingAutocomplete()) {
					super.handleInput(data);
				} else {
					this.mode = "normal";
				}
			} else {
				super.handleInput(data);
			}
			return;
		}

		if (this.mode === "insert") {
			super.handleInput(data);
			return;
		}

		if (matchesKey(data, "enter")) {
			this.mode = "insert";
			super.handleInput(data);
			return;
		}

		const printable = decodeKittyPrintable(data);
		const key = printable ?? data;

		if (key === "i") {
			this.mode = "insert";
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

		const isPrintable =
			printable !== undefined ||
			(data.length > 0 &&
				[...data].every((character) => {
					const codePoint = character.codePointAt(0) ?? 0;
					return codePoint >= 32 && codePoint !== 127;
				}));
		if (isPrintable) return;
		super.handleInput(data);
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
