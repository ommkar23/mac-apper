import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { readFile } from "node:fs/promises";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";

const projectRoot = resolve(fileURLToPath(new URL("../..", import.meta.url)));
const skillPath = fileURLToPath(new URL("../skills/multi-agent-handoff/SKILL.md", import.meta.url));
const agentTypes = ["coordinator", "researcher", "worker", "reviewer"] as const;
type AgentType = typeof agentTypes[number];

export function resolveAgentType(value: string | undefined): AgentType {
  if (value === undefined) return "coordinator";
  if (agentTypes.includes(value as AgentType)) return value as AgentType;
  throw new Error("AGENT_TYPE must be coordinator, researcher, worker, or reviewer; unset it for coordinator.");
}

export default function multiAgentHandoff(pi: ExtensionAPI) {
  const role = resolveAgentType(process.env.AGENT_TYPE);
  let instructions = "";

  pi.on("resources_discover", () => ({ skillPaths: [skillPath] }));

  pi.on("session_start", async (_event, ctx) => {
    instructions = "";
    if (resolve(ctx.cwd) !== projectRoot) return;
    const source = await readFile(new URL(`../resources/multi-agent-handoff/${role}.txt`, import.meta.url), "utf8");
    if (!source.trim()) throw new Error(`Missing instructions for AGENT_TYPE=${role}`);
    instructions = `Agent role: ${role}\n\n${source.trim()}`;
  });

  pi.on("before_agent_start", (event, ctx) => {
    if (resolve(ctx.cwd) !== projectRoot || !instructions) return;
    event.systemPromptOptions.sections.multi_agent_handoff = instructions;
  });
}
