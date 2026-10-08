import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";

export default function (pi: ExtensionAPI) {
	let timer: ReturnType<typeof setInterval> | undefined;
	let lastStatus: string | undefined | null = null;

	const refresh = (ctx: ExtensionContext) => {
		if (ctx.mode !== "tui") return;
		const name = ctx.sessionManager.getSessionName();
		const status = name
			? ctx.ui.theme.style(` ${name} `, {
				fg: name === "manager" ? { kind: "rgb", r: 255, g: 255, b: 255 } : "text",
				bg: name === "manager" ? ctx.ui.theme.colors.warning : "selectedBg",
				bold: true,
			})
			: undefined;
		if (status !== lastStatus) {
			ctx.ui.setStatus("session-name", status);
			lastStatus = status;
		}
	};

	const stop = () => {
		clearInterval(timer);
		timer = undefined;
	};

	pi.on("session_start", (_event, ctx) => {
		stop();
		lastStatus = null;
		refresh(ctx);
		if (ctx.mode !== "tui") return;
		// Status strings retain ANSI colors; refresh them when the active theme changes.
		timer = setInterval(() => refresh(ctx), 1000);
		timer.unref();
	});

	pi.on("session_info_changed", (_event, ctx) => refresh(ctx));

	pi.on("session_shutdown", (_event, ctx) => {
		stop();
		if (ctx.mode === "tui") ctx.ui.setStatus("session-name", undefined);
		lastStatus = undefined;
	});
}
