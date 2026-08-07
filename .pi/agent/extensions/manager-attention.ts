import { homedir } from "node:os";
import { join } from "node:path";
import type { AssistantMessage } from "@earendil-works/pi-ai";
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";

// Task: /Volumes/dev/_tasks/env/0030-transient-pi-manager-attention/task.md
const MANAGER_MARKER = `[${"MM" + "_NTF"}]`;
const QA_PROMPT = "Send an MM_NTF synthetic Manager decision now.";
const WIDGET_ID = "manager-attention";
const ATTENTION_HELPER = join(homedir(), ".dots/no_stow/bin/tmux/agent-attention-notify");

type WorkflowAttentionReason = "issue" | "squash" | "rebase" | "failure";

function isWorkflowCommand(command: string): boolean {
	return (
		command.includes("/Volumes/dev/bin/skills/autofix ") ||
		command.includes("/Volumes/dev/bin/skills/autoimplement ")
	);
}

function workflowAttentionReason(output: string, is_error: boolean): WorkflowAttentionReason | undefined {
	if (is_error) return "failure";
	if (/^Issue: \d+$/m.test(output)) return "issue";
	if (/^AutoFixSquash \d+$/m.test(output)) return "squash";
	if (/^RebaseConflict \d+$/m.test(output)) return "rebase";

	return undefined;
}

function withManagerMarker(message: AssistantMessage): AssistantMessage {
	const text_index = message.content.findIndex((block) => block.type === "text");
	if (text_index === -1) return message;

	const text_block = message.content[text_index];
	if (text_block?.type !== "text" || text_block.text.startsWith(MANAGER_MARKER)) return message;

	const content = [...message.content];
	content[text_index] = {
		...text_block,
		text: `${MANAGER_MARKER}${text_block.text}`,
	};

	return { ...message, content };
}

function withoutManagerMarker(message: AssistantMessage): AssistantMessage | undefined {
	const text_index = message.content.findIndex((block) => block.type === "text");
	if (text_index === -1) return undefined;

	const text_block = message.content[text_index];
	if (text_block?.type !== "text" || !text_block.text.startsWith(MANAGER_MARKER)) return undefined;

	const content = [...message.content];
	content[text_index] = {
		...text_block,
		text: text_block.text.slice(MANAGER_MARKER.length),
	};

	return { ...message, content };
}

export default function managerAttentionExtension(pi: ExtensionAPI): void {
	let is_attention_active = false;
	let is_qa_response_pending = false;
	let workflow_attention_reason: WorkflowAttentionReason | undefined;

	async function runAttentionHelper(operation: "--manager-set" | "--manager-clear"): Promise<void> {
		const pane_id = process.env.TMUX_PANE?.trim();
		if (!pane_id) return;

		try {
			await pi.exec(ATTENTION_HELPER, [operation, pane_id], { timeout: 5000 });
		} catch {
			// Attention is best-effort; message finalization and input must continue.
		}
	}

	async function showAttention(ctx: ExtensionContext): Promise<void> {
		is_attention_active = true;
		try {
			ctx.ui.setWidget(WIDGET_ID, [`${MANAGER_MARKER} Decision required`]);
		} catch {
			// Tmux/macOS attention must still run if widget rendering fails.
		}
		await runAttentionHelper("--manager-set");
	}

	async function clearAttention(ctx: ExtensionContext): Promise<void> {
		is_attention_active = false;
		try {
			ctx.ui.setWidget(WIDGET_ID, undefined);
		} catch {
			// Tmux attention must still clear if widget rendering fails.
		}
		await runAttentionHelper("--manager-clear");
	}

	pi.on("before_agent_start", async (event) => {
		is_qa_response_pending = event.prompt.trim() === QA_PROMPT;
	});

	pi.on("tool_result", async (event) => {
		if (event.toolName !== "bash") return;

		const command = typeof event.input.command === "string" ? event.input.command : "";
		if (!isWorkflowCommand(command)) return;

		const output = event.content
			.filter((block) => block.type === "text")
			.map((block) => block.text)
			.join("\n");
		workflow_attention_reason = workflowAttentionReason(output, event.isError);
	});

	pi.on("message_end", async (event, ctx) => {
		if (event.message.role !== "assistant") return;

		let message = event.message;
		if ((is_qa_response_pending || workflow_attention_reason) && message.stopReason === "stop") {
			is_qa_response_pending = false;
			message = withManagerMarker(message);
			if (workflow_attention_reason === "failure") workflow_attention_reason = undefined;
		}

		const replacement = withoutManagerMarker(message);
		if (!replacement) return;

		if (ctx.mode === "tui" || ctx.hasUI) {
			await showAttention(ctx);
		}
		return { message: replacement };
	});

	pi.on("input", async (event, ctx) => {
		if (
			event.source !== "extension" &&
			workflow_attention_reason === "squash" &&
			/^(?:no|skip|leave)$/i.test(event.text.trim())
		) {
			workflow_attention_reason = undefined;
		}
		if (event.source === "extension" || !is_attention_active) {
			return { action: "continue" };
		}

		await clearAttention(ctx);
		return { action: "continue" };
	});

	pi.on("session_start", async (_event, ctx) => {
		await clearAttention(ctx);
	});

	pi.on("session_shutdown", async (_event, ctx) => {
		await clearAttention(ctx);
	});
}
