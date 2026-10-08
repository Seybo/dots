import assert from "node:assert/strict";
import test from "node:test";
import extension from "./index.ts";

function setup() {
    const handlers = new Map<string, (args: string, ctx: any) => Promise<void>>();
    const calls: { command: string; args: string[]; options: any }[] = [];
    const messages: any[] = [];
    const notices: { text: string; level: string }[] = [];
    let response = { code: 0, stdout: JSON.stringify({ id: "uuid", identifier: "HC-123", title: "Fix checkout", description: "Body", url: "URL", branchName: "provider/branch" }), stderr: "", killed: false };
    const pi = {
        registerCommand: (name: string, command: any) => handlers.set(name, command.handler),
        exec: async (command: string, args: string[], options: any) => { calls.push({ command, args, options }); return response; },
        sendMessage: (message: any) => messages.push(message),
    };
    extension(pi as any);
    const ctx = { cwd: "/checkout", ui: { notify: (text: string, level: string) => notices.push({ text, level }) } };
    return { handlers, calls, messages, notices, ctx, fail: () => { response = { ...response, code: 1, stderr: "Denied", stdout: "" }; } };
}

test("registers only explicit read/create/update commands", () => {
    const state = setup();
    assert.deepEqual([...state.handlers.keys()], ["linear-issue-read", "linear-issue-create", "linear-issue-update"]);
    assert.equal(state.calls.length, 0);
});

test("read injects fetched JSON as agent context without triggering a write", async () => {
    const state = setup();
    await state.handlers.get("linear-issue-read")!("HC-123", state.ctx);
    assert.deepEqual(state.calls[0].args.slice(1), ["get-issue", "HC-123"]);
    assert.equal(state.calls[0].options.cwd, "/checkout");
    assert.match(state.messages[0].content, /HC-123/);
    assert.match(state.messages[0].content, /Body/);
});

test("creation handles a quoted title and description path", async () => {
    const state = setup();
    await state.handlers.get("linear-issue-create")!('shaka_hc "Fix checkout" Bug "./my task.md"', state.ctx);
    assert.deepEqual(state.calls[0].args.slice(1, 3), ["create-issue", "shaka_hc"]);
    assert.deepEqual(JSON.parse(state.calls[0].args[3]), { title: "Fix checkout", type: "Bug", description_path: "./my task.md" });
    assert.match(state.messages[0].content, /provider\/branch/);
});

test("creation accepts explicit requester JSON", async () => {
    const state = setup();
    const json = '{"title":"Fix","type":"Bug","assignee_id":"requester"}';
    await state.handlers.get("linear-issue-create")!(`shaka_hc ${json}`, state.ctx);
    assert.equal(state.calls[0].args[3], json);
});

test("updates permit identifier-only lookup and quoted file paths", async () => {
    const state = setup();
    await state.handlers.get("linear-issue-update")!("HC-123", state.ctx);
    await state.handlers.get("linear-issue-update")!('HC-123 "./my task.md"', state.ctx);
    assert.deepEqual(state.calls[0].args.slice(1), ["update-issue", "HC-123"]);
    assert.deepEqual(state.calls[1].args.slice(1), ["update-issue", "HC-123", "./my task.md"]);
});

test("malformed command arguments do not execute the CLI", async () => {
    const state = setup();
    await state.handlers.get("linear-issue-create")!('shaka_hc "unfinished', state.ctx);
    await state.handlers.get("linear-issue-update")!("", state.ctx);
    assert.equal(state.calls.length, 0);
    assert.equal(state.notices.length, 2);
});

test("CLI failure produces no success context and does not retry", async () => {
    const state = setup();
    state.fail();
    await state.handlers.get("linear-issue-create")!('shaka_hc "Fix" Bug', state.ctx);
    assert.equal(state.calls.length, 1);
    assert.equal(state.messages.length, 0);
    assert.match(state.notices[0].text, /Denied/);
    assert.equal(state.notices[0].level, "error");
});
