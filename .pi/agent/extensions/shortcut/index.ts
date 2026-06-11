import { execFile } from "node:child_process"
import { tmpdir } from "node:os"
import { fileURLToPath } from "node:url"
import { existsSync, mkdtempSync, readFileSync, readdirSync, statSync, writeFileSync } from "node:fs"
import { dirname, join } from "node:path"
import type { ExtensionAPI } from "@mariozechner/pi-coding-agent"

const __dirname = dirname(fileURLToPath(import.meta.url))
const shortcutScript = join(__dirname, "scripts", "shortcut.rb")

type ShortcutStory = {
    app_url?: string
    completed?: boolean
    description?: string
    epic_id?: number
    estimate?: number
    id?: number
    name?: string
    owner_ids?: string[]
    project_id?: number
    story_type?: string
    workflow_state_id?: number
}

type RubyResult = {
    stdout: string
    stderr: string
}

export default function (pi: ExtensionAPI) {
    pi.registerCommand("shortcut-story-read", {
        description: "Read Shortcut stories by IDs or Shortcut story links. Usage: /shortcut-story-read <id-or-link> [...]",
        handler: async (args, ctx) => {
            const storyIds = parseStoryIds(args)

            if (storyIds.length === 0) {
                ctx.ui.notify("Usage: /shortcut-story-read <id-or-link> [...]", "info")
                return
            }

            try {
                ctx.ui.notify(await readStories(storyIds, ctx.signal), "info")
            } catch (err: unknown) {
                const message = err instanceof Error ? err.message : String(err)
                ctx.ui.notify(`Shortcut story read failed: ${message}`, "error")
            }
        },
    })

    pi.registerCommand("shortcut-story-create", {
        description: 'Create a Shortcut story in Ready. Usage: /shortcut-story-create "Story name" 123 [description.md]',
        handler: async (args, ctx) => {
            const payload = parseCreateStoryArgs(args)

            if (!payload) {
                ctx.ui.notify('Usage: /shortcut-story-create "Story name" 123 [description.md]', "info")
                return
            }

            try {
                const story = await createStory(payload, ctx.signal)
                ctx.ui.notify(`Created ${formatStory(story)}`, "info")
            } catch (err: unknown) {
                const message = err instanceof Error ? err.message : String(err)
                ctx.ui.notify(`Shortcut story create failed: ${message}`, "error")
            }
        },
    })

    pi.registerCommand("shortcut-story-update", {
        description: "Update a Shortcut story description from markdown. Usage: /shortcut-story-update <id-or-link> [description.md]",
        handler: async (args, ctx) => {
            const updateArgs = parseUpdateStoryArgs(args)

            if (!updateArgs) {
                ctx.ui.notify("Usage: /shortcut-story-update <id-or-link> [description.md]", "info")
                return
            }

            try {
                await updateStory(updateArgs.storyId, updateArgs.descriptionPath, ctx.signal)
                ctx.ui.notify(`Done. Updated Shortcut story ${updateArgs.storyId}.`, "info")
            } catch (err: unknown) {
                const message = err instanceof Error ? err.message : String(err)
                ctx.ui.notify(`Shortcut story update failed: ${message}`, "error")
            }
        },
    })

    pi.on("input", async (event, ctx) => {
        if (isUpdateStoryRequest(event.text)) {
            const updateArgs = parseUpdateStoryArgs(event.text)
            if (!updateArgs) return { action: "continue" as const }

            try {
                await updateStory(updateArgs.storyId, updateArgs.descriptionPath, ctx.signal)
                return {
                    action: "transform" as const,
                    text: `${event.text}\n\nDone. Updated Shortcut story ${updateArgs.storyId}.`,
                }
            } catch (err: unknown) {
                const message = err instanceof Error ? err.message : String(err)
                return {
                    action: "transform" as const,
                    text: `${event.text}\n\nShortcut story update failed before answering: ${message}`,
                }
            }
        }

        if (!isReadStoryRequest(event.text)) return { action: "continue" as const }

        const storyIds = parseStoryIds(event.text)
        if (storyIds.length === 0) return { action: "continue" as const }

        try {
            const stories = await readStories(storyIds, ctx.signal)
            return {
                action: "transform" as const,
                text: `${event.text}\n\nFetched Shortcut story contents:\n\n${stories}`,
            }
        } catch (err: unknown) {
            const message = err instanceof Error ? err.message : String(err)
            return {
                action: "transform" as const,
                text: `${event.text}\n\nShortcut story read failed before answering: ${message}`,
            }
        }
    })
}

function parseCreateStoryArgs(args: string): string | undefined {
    const trimmed = args.trim()
    if (trimmed.startsWith("{")) return trimmed

    const doubleQuoted = trimmed.match(/^"([^"]+)"\s*,?\s*(\S+)(?:\s+(\S+))?$/)
    if (doubleQuoted?.[1] && doubleQuoted[2]) {
        return createStoryPayload(doubleQuoted[1], doubleQuoted[2], doubleQuoted[3])
    }

    const singleQuoted = trimmed.match(/^'([^']+)'\s*,?\s*(\S+)(?:\s+(\S+))?$/)
    if (singleQuoted?.[1] && singleQuoted[2]) {
        return createStoryPayload(singleQuoted[1], singleQuoted[2], singleQuoted[3])
    }

    return undefined
}

function createStoryPayload(name: string, epicValue: string, descriptionPath?: string): string | undefined {
    const epicId = parseEpicId(epicValue)
    if (!epicId) return undefined

    return JSON.stringify({
        name,
        epic_id: Number(epicId),
        ...(descriptionPath ? { description_path: descriptionPath } : {}),
    })
}

function parseEpicId(value: string): string | undefined {
    const epicUrl = value.match(/\/epic\/(\d+)\b/i)
    if (epicUrl?.[1]) return epicUrl[1]

    return /^\d+$/.test(value) ? value : undefined
}

function parseUpdateStoryArgs(text: string): { storyId: string; descriptionPath: string } | undefined {
    const storyIds = parseStoryIds(text)
    const storyId = storyIds[0]
    if (storyIds.length !== 1 || !storyId) return undefined

    const descriptionPath = parseMarkdownPath(text) ?? findTaskMarkdownForStory(storyId)
    if (!descriptionPath) return undefined

    return { storyId, descriptionPath }
}

function findTaskMarkdownForStory(storyId: string): string | undefined {
    const tasksRoot = "/Volumes/dev/_tasks"
    if (!existsSync(tasksRoot)) return undefined

    const matches: string[] = []
    for (const projectName of readdirSync(tasksRoot)) {
        const projectPath = join(tasksRoot, projectName)
        if (!statSync(projectPath).isDirectory()) continue

        for (const taskFolder of readdirSync(projectPath)) {
            if (!taskFolder.startsWith(`${storyId}-`)) continue

            const taskPath = join(projectPath, taskFolder, "task.md")
            if (existsSync(taskPath)) matches.push(taskPath)
        }
    }

    return matches.length === 1 ? matches[0] : undefined
}

function parseMarkdownPath(text: string): string | undefined {
    const match = text.match(/(?:^|\s)(\S+\.(?:md|markdown))\b/i)
    return match?.[1]
}

async function createStory(rawJson: string, signal?: AbortSignal): Promise<ShortcutStory> {
    const result = await runShortcut(["create-story", rawJson], signal)
    return JSON.parse(result.stdout) as ShortcutStory
}

async function updateStory(storyId: string, descriptionPath: string, signal?: AbortSignal): Promise<ShortcutStory> {
    const cleanedDescriptionPath = stripStoryDetailsSection(descriptionPath)
    const result = await runShortcut(["update-story", storyId, cleanedDescriptionPath], signal)
    return JSON.parse(result.stdout) as ShortcutStory
}

function stripStoryDetailsSection(descriptionPath: string): string {
    const markdown = readFileSync(descriptionPath, "utf8")
    const lines = markdown.split(/\r?\n/)
    const start = lines.findIndex((line) => line === "# Story details")
    if (start === -1) return descriptionPath

    let end = lines.length
    for (let i = start + 1; i < lines.length; i += 1) {
        if (lines[i]?.startsWith("# ")) {
            end = i
            break
        }
    }

    const stripped = [...lines.slice(0, start), ...lines.slice(end)].join("\n").replace(/^\n+/, "")
    const dir = mkdtempSync(join(tmpdir(), "shortcut-story-update-"))
    const cleanedPath = join(dir, "description.md")
    writeFileSync(cleanedPath, stripped.endsWith("\n") ? stripped : `${stripped}\n`)
    return cleanedPath
}

async function readStories(storyIds: string[], signal?: AbortSignal): Promise<string> {
    const stories = []

    for (const storyId of storyIds) {
        const result = await runShortcut(["get-story", storyId], signal)
        const story = JSON.parse(result.stdout) as ShortcutStory
        stories.push(formatStory(story))
    }

    return stories.join("\n\n---\n\n")
}

function parseStoryIds(text: string): string[] {
    const storyIds: string[] = []
    const seen = new Set<string>()

    const addStoryId = (storyId: string) => {
        if (seen.has(storyId)) return

        seen.add(storyId)
        storyIds.push(storyId)
    }

    for (const match of text.matchAll(/\/(?:story|stories)\/(\d+)\b/gi)) {
        const storyId = match[1]
        if (storyId) addStoryId(storyId)
    }

    for (const match of text.matchAll(/(?:^|[\s,#])(\d+)\b/g)) {
        const storyId = match[1]
        if (storyId) addStoryId(storyId)
    }

    return storyIds
}

function isReadStoryRequest(text: string): boolean {
    return /\bread\s+(?:shortcut\s+)?(?:(?:these|this)\s+)?stor(?:y|ies)\b/i.test(text)
}

function isUpdateStoryRequest(text: string): boolean {
    return /\bupdate\s+(?:shortcut\s+)?(?:(?:these|this)\s+)?stor(?:y|ies)\b/i.test(text)
}

function runShortcut(args: string[], signal?: AbortSignal): Promise<RubyResult> {
    return new Promise((resolve, reject) => {
        const child = execFile("ruby", [shortcutScript, ...args], { signal }, (error, stdout, stderr) => {
            if (error) {
                const stderrText = stderr.toString().trim()
                reject(new Error(stderrText || error.message))
                return
            }

            resolve({ stdout: stdout.toString(), stderr: stderr.toString() })
        })

        child.stdin?.end()
    })
}

function formatStory(story: ShortcutStory): string {
    const lines = [
        `Shortcut Story #${story.id ?? "unknown"}: ${story.name ?? "(untitled)"}`,
        story.app_url ? `URL: ${story.app_url}` : undefined,
        `Type: ${story.story_type ?? "unknown"}`,
        `Completed: ${story.completed === undefined ? "unknown" : story.completed}`,
        story.workflow_state_id ? `Workflow State ID: ${story.workflow_state_id}` : undefined,
        story.epic_id ? `Epic ID: ${story.epic_id}` : undefined,
        story.project_id ? `Project ID: ${story.project_id}` : undefined,
        story.estimate === undefined || story.estimate === null ? undefined : `Estimate: ${story.estimate}`,
        story.owner_ids && story.owner_ids.length > 0 ? `Owner IDs: ${story.owner_ids.join(", ")}` : undefined,
        story.description ? `\nDescription:\n${story.description}` : undefined,
    ].filter((line): line is string => line !== undefined)

    return lines.join("\n")
}
