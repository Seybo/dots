export type CopyArgs = {
	mode: string;
	selector?: string;
};

export type Selection =
	| { kind: "picker" }
	| { kind: "item"; item: string }
	| { kind: "invalid" };

export function parseCopyArgs(args: string): CopyArgs | undefined {
	const input = args.trim();
	if (!input) return undefined;

	const parts = input.split(/\s+/);
	if (parts.length > 2) return undefined;

	const [mode, selector] = parts;
	return selector ? { mode: mode!, selector } : { mode: mode! };
}

export function resolveSelection(items: string[], selector: string | undefined): Selection {
	if (selector === undefined) return { kind: "picker" };

	let index: number;
	if (selector === "l") index = items.length - 1;
	else if (/^[1-9]\d*$/.test(selector)) index = Number(selector) - 1;
	else return { kind: "invalid" };

	const item = items[index];
	return item === undefined ? { kind: "invalid" } : { kind: "item", item };
}
