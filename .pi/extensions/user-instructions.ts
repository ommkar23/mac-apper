import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { readFile } from "node:fs/promises";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";

const projectRoot = resolve(fileURLToPath(new URL("../..", import.meta.url)));
const instructionsFile = new URL("../resources/user-instructions.txt", import.meta.url);

export function parseInstructions(source: string): string[] {
  return source.split(/\r?\n/u).map((line) => line.trim()).filter(Boolean);
}

export default function userInstructions(pi: ExtensionAPI) {
  let instructions: string[] = [];

  pi.on("session_start", async (_event, ctx) => {
    instructions = [];
    if (resolve(ctx.cwd) !== projectRoot) return;
    instructions = parseInstructions(await readFile(instructionsFile, "utf8"));
  });

  pi.on("before_agent_start", (event, ctx) => {
    if (resolve(ctx.cwd) !== projectRoot || instructions.length === 0) return;
    event.systemPromptOptions.sections.user_instructions =
      "Project user instructions:\n\n" + instructions.map((instruction) => `- ${instruction}`).join("\n");
  });
}
