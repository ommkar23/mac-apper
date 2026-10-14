import assert from "node:assert/strict";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import userInstructions, { parseInstructions } from "../extensions/user-instructions.ts";

const root = fileURLToPath(new URL("../../", import.meta.url));

test("parses plain-text instructions, trimming lines and ignoring blank lines", () => {
  assert.deepEqual(parseInstructions("\n First instruction. \r\n\nSecond instruction.\n"),
    ["First instruction.", "Second instruction."]);
  assert.deepEqual(parseInstructions(" \n"), []);
});

test("loads at session start and applies a stable project-only prompt section", async () => {
  const handlers = new Map();
  userInstructions({ on: (event, handler) => handlers.set(event, handler) });
  const event = () => ({ systemPromptOptions: { sections: { existing: "preserve" } } });
  const before = event();
  handlers.get("before_agent_start")(before, { cwd: root });
  assert.deepEqual(before.systemPromptOptions.sections, { existing: "preserve" });
  await handlers.get("session_start")({}, { cwd: root });
  const first = event();
  handlers.get("before_agent_start")(first, { cwd: root });
  assert.match(first.systemPromptOptions.sections.user_instructions, /concise.*list and sublist/s);
  assert.equal(first.systemPromptOptions.sections.existing, "preserve");
  const later = event();
  handlers.get("before_agent_start")(later, { cwd: root });
  assert.deepEqual(later, first);
  const foreign = event();
  handlers.get("before_agent_start")(foreign, { cwd: "/private/tmp" });
  assert.deepEqual(foreign.systemPromptOptions.sections, { existing: "preserve" });
  await handlers.get("session_start")({}, { cwd: "/private/tmp" });
  const cleared = event();
  handlers.get("before_agent_start")(cleared, { cwd: root });
  assert.deepEqual(cleared.systemPromptOptions.sections, { existing: "preserve" });
});
