import { resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { Type } from "@earendil-works/pi-ai";
import { withFileMutationQueue, type ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { collectSwiftFrontmatter, getSwiftFrontmatter, removeSwiftFrontmatter, setSwiftFrontmatter } from "../lib/swift-frontmatter.ts";

const projectRoot = resolve(fileURLToPath(new URL("../..", import.meta.url)));
const pathParameters = Type.Object({
  path: Type.String({ description: "Project-relative path to an existing .swift file" }),
});

export default function swiftFrontmatter(pi: ExtensionAPI) {
  pi.registerTool({
    name: "add_frontmatter",
    label: "Set Swift frontmatter",
    description: "Set or replace the delimited top-of-file frontmatter of an existing project Swift file. Content must briefly describe what code in this file does, never other related files. Provide content as Swift line comments; it is inserted verbatim.",
    parameters: Type.Object({
      path: Type.String({ description: "Project-relative path to an existing .swift file" }),
      content: Type.String({ description: "Brief description of what the code in this file does, written as Swift line comments (// ...); inserted verbatim. Do not describe related files." }),
    }),
    async execute(_toolCallId, params, _signal, _onUpdate, ctx) {
      if (resolve(ctx.cwd) !== projectRoot) throw new Error("This tool only operates from its project root");
      await withFileMutationQueue(resolve(projectRoot, params.path), async () => {
        setSwiftFrontmatter(projectRoot, params);
      });
      return {
        content: [{ type: "text", text: `Updated frontmatter: ${params.path}` }],
        details: { path: params.path },
      };
    },
  });

  pi.registerTool({
    name: "get_frontmatter",
    label: "Get Swift frontmatter",
    description: "Retrieve the verbatim comment content between frontmatter markers in an existing project Swift file. Returns a notice if absent.",
    parameters: pathParameters,
    async execute(_toolCallId, params, _signal, _onUpdate, ctx) {
      if (resolve(ctx.cwd) !== projectRoot) throw new Error("This tool only operates from its project root");
      const content = await withFileMutationQueue(resolve(projectRoot, params.path), async () =>
        getSwiftFrontmatter(projectRoot, params.path));
      return {
        content: [{ type: "text", text: content ?? `No frontmatter: ${params.path}` }],
        details: { path: params.path, found: content !== undefined },
      };
    },
  });

  pi.registerTool({
    name: "remove_frontmatter",
    label: "Remove Swift frontmatter",
    description: "Remove only the delimited frontmatter from an existing project Swift file, preserving the rest of the file. No-op if absent.",
    parameters: pathParameters,
    async execute(_toolCallId, params, _signal, _onUpdate, ctx) {
      if (resolve(ctx.cwd) !== projectRoot) throw new Error("This tool only operates from its project root");
      const removed = await withFileMutationQueue(resolve(projectRoot, params.path), async () =>
        removeSwiftFrontmatter(projectRoot, params.path));
      return {
        content: [{ type: "text", text: removed ? `Removed frontmatter: ${params.path}` : `No frontmatter: ${params.path}` }],
        details: { path: params.path, removed },
      };
    },
  });

  pi.on("before_agent_start", (event, ctx) => {
    if (resolve(ctx.cwd) !== projectRoot) return;
    try {
      const briefs = collectSwiftFrontmatter(projectRoot);
      if (briefs) event.systemPromptOptions.sections.project_file_briefs = `Swift file briefs (relative to project root):\n\n${briefs}`;
      else delete event.systemPromptOptions.sections.project_file_briefs;
    } catch (error) {
      console.error("Could not load Swift frontmatter:", error);
    }
  });
}
