import assert from "node:assert/strict";
import { test } from "node:test";
import { access, readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import multiAgentHandoff, { resolveAgentType } from "../extensions/multi-agent-handoff.ts";
import userInstructions from "../extensions/user-instructions.ts";

const root = fileURLToPath(new URL("../../", import.meta.url));
const event = () => ({ systemPromptOptions: { sections: { existing: "preserve" } } });

function harness() {
  const handlers = new Map();
  const pi = { on(name, handler) {
    const list = handlers.get(name) ?? [];
    list.push(handler);
    handlers.set(name, list);
  } };
  return { pi, async emit(name, value, ctx = { cwd: root }) {
    const results = [];
    for (const handler of handlers.get(name) ?? []) results.push(await handler(value, ctx));
    return results;
  } };
}

async function withRole(role, run) {
  const original = process.env.AGENT_TYPE;
  try {
    if (role === undefined) delete process.env.AGENT_TYPE;
    else process.env.AGENT_TYPE = role;
    await run();
  } finally {
    if (original === undefined) delete process.env.AGENT_TYPE;
    else process.env.AGENT_TYPE = original;
  }
}

test("defaults only an unset AGENT_TYPE and rejects invalid values", () => {
  assert.equal(resolveAgentType(undefined), "coordinator");
  for (const role of ["coordinator", "researcher", "worker", "reviewer"]) {
    assert.equal(resolveAgentType(role), role);
  }
  for (const role of ["", "Worker", " worker ", "other", "../worker", "toString"]) {
    assert.throws(() => resolveAgentType(role), /AGENT_TYPE/);
  }
});

test("exposes the canonical skill and isolates role instructions without replacing shared instructions", async () => {
  for (const role of [undefined, "coordinator", "researcher", "worker", "reviewer"]) {
    await withRole(role, async () => {
      const h = harness();
      multiAgentHandoff(h.pi);
      userInstructions(h.pi);
      const [resources] = await h.emit("resources_discover", {});
      assert.deepEqual(resources.skillPaths, [fileURLToPath(new URL("../skills/multi-agent-handoff/SKILL.md", import.meta.url))]);
      await access(resources.skillPaths[0]);
      const before = event();
      await h.emit("before_agent_start", before);
      assert.deepEqual(before.systemPromptOptions.sections, { existing: "preserve" });
      await h.emit("session_start", {});
      const first = event();
      await h.emit("before_agent_start", first);
      const text = first.systemPromptOptions.sections.multi_agent_handoff;
      assert.match(text, new RegExp(`Agent role: ${role ?? "coordinator"}`));
      assert.match(text, new RegExp(`Access: ${role === "worker" ? "write" : "read-only"}`));
      if (!role || role === "coordinator") {
        assert.match(text, /user interacts only with the coordinator/);
        assert.match(text, /All file changes.*through implementing workers/);
        assert.match(text, /does not.*run tests/s);
      }
      if (role === "researcher") assert.match(text, /does not.*edit files/s);
      assert.doesNotMatch(text, /callback/i);
      if (!role || role === "coordinator") {
        assert.match(text, /researcher.*3 minutes/);
        assert.match(text, /worker.*5 minutes/);
        assert.match(text, /reviewer.*2 minutes/);
        assert.match(text, /user.*explicit.*duration/i);
      }
      assert.match(first.systemPromptOptions.sections.user_instructions, /Project user instructions/);
      assert.equal(first.systemPromptOptions.sections.existing, "preserve");
      if (role === "reviewer") assert.match(text, /does not.*run tests/s);
      if (role === "worker") assert.match(text, /assigned files/);
      if (role === "researcher") assert.match(text, /does not authorize implementation/);
      if (!role || role === "coordinator") assert.match(text, /authorization/);
      const later = event();
      await h.emit("before_agent_start", later);
      assert.deepEqual(later, first);
      const foreign = event();
      await h.emit("before_agent_start", foreign, { cwd: "/" });
      assert.deepEqual(foreign.systemPromptOptions.sections, { existing: "preserve" });
      await h.emit("session_start", {}, { cwd: "/" });
      const cleared = event();
      await h.emit("before_agent_start", cleared);
      assert.deepEqual(cleared.systemPromptOptions.sections, { existing: "preserve" });
    });
  }
});

test("handoff skills use coordinator polling rather than agent callbacks", async () => {
  for (const skill of ["agent-handoff", "multi-agent-handoff"]) {
    const source = await readFile(new URL(`../skills/${skill}/SKILL.md`, import.meta.url), "utf8");
    assert.doesNotMatch(source, /callback/i);
    assert.match(source, /researcher.*3 minutes/);
    assert.match(source, /worker.*5 minutes/);
    assert.match(source, /reviewer.*2 minutes/);
    assert.match(source, /user.*explicit.*duration/i);
    assert.match(source, /own.*response/);
  }
});

test("role is captured at extension load rather than changed by later environment mutations", async () => {
  await withRole("reviewer", async () => {
    const h = harness();
    multiAgentHandoff(h.pi);
    process.env.AGENT_TYPE = "worker";
    await h.emit("session_start", {});
    const request = event();
    await h.emit("before_agent_start", request);
    assert.match(request.systemPromptOptions.sections.multi_agent_handoff, /^Agent role: reviewer/);
  });
});

test("invalid roles fail explicitly rather than silently becoming coordinator", async () => {
  await withRole("invalid", async () => {
    assert.throws(() => multiAgentHandoff(harness().pi), /AGENT_TYPE/);
  });
});
