import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";

type Mode = "lite" | "full" | "ultra" | "wenyan" | "wenyan-lite" | "wenyan-full" | "wenyan-ultra";

export default function (pi: ExtensionAPI) {
	let activeMode: Mode | undefined;

	const render = (ctx: any) => {
		if (!activeMode) {
			ctx.ui.setStatus("caveman", undefined);
			return;
		}

		const theme = ctx.ui.theme;
		const label = activeMode === "full" ? "CAVEMAN" : `CAVEMAN:${activeMode.toUpperCase()}`;
		ctx.ui.setStatus("caveman", theme.fg("accent", `🪨 ${label}`));
	};

	const parseMode = (text: string): Mode => {
		const lower = text.toLowerCase();
		if (/(^|\s)wenyan-ultra(\s|$)/.test(lower)) return "wenyan-ultra";
		if (/(^|\s)wenyan-lite(\s|$)/.test(lower)) return "wenyan-lite";
		if (/(^|\s)wenyan-full(\s|$)/.test(lower)) return "wenyan-full";
		if (/(^|\s)wenyan(\s|$)/.test(lower)) return "wenyan";
		if (/(^|\s)ultra(\s|$)/.test(lower)) return "ultra";
		if (/(^|\s)lite(\s|$)/.test(lower)) return "lite";
		return "full";
	};

	const isActivate = (text: string) => {
		const lower = text.toLowerCase();
		return (
			/^\/skill:caveman\b/.test(lower) ||
			/\bcaveman mode\b/.test(lower) ||
			/\btalk like caveman\b/.test(lower) ||
			/\buse caveman\b/.test(lower) ||
			/\bless tokens\b/.test(lower) ||
			/\bbe brief\b/.test(lower)
		);
	};

	const isDeactivate = (text: string) => /\bstop caveman\b|\bnormal mode\b/i.test(text);

	pi.on("session_start", async (_event, ctx) => {
		render(ctx);
	});

	pi.on("input", async (event, ctx) => {
		const text = event.text.trim();
		if (!text) return { action: "continue" };

		if (isDeactivate(text)) {
			activeMode = undefined;
			render(ctx);
			return { action: "continue" };
		}

		if (isActivate(text)) {
			activeMode = parseMode(text);
			render(ctx);
			return { action: "continue" };
		}

		return { action: "continue" };
	});
};
