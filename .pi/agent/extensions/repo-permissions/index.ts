import { parseFrontmatter, type ExtensionAPI } from "@earendil-works/pi-coding-agent";

import { registerRepoPermissions } from "./extension.ts";

export default function repoPermissionsExtension(pi: ExtensionAPI): void {
	registerRepoPermissions(pi, (content) => parseFrontmatter<Record<string, unknown>>(content).frontmatter);
}
