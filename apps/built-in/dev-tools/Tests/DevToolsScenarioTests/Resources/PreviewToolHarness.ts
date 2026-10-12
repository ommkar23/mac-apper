// Test-only Pi registration harness; all transport is performed by the unmodified generated extension and packaged client.
import { pathToFileURL } from "node:url";
let input = "";
for await (const chunk of process.stdin) {
  input += chunk.toString();
  if (Buffer.byteLength(input) > 16384) throw Error("oversized test request");
}
const request = JSON.parse(input);
if (request.readPath !== undefined) {
  // Import only the installed production filesystem tool; no Pi session, extension loader or MCP.
  const modulePath = process.env.DEV_TOOLS_SCENARIO_PI_READ_MODULE;
  if (!modulePath?.startsWith("/")) throw Error("installed production read module required");
  const { createReadToolDefinition } = await import(pathToFileURL(modulePath).href);
  const read = createReadToolDefinition(process.env.OPENXPC_PROJECT_ROOT);
  const result = await read.execute("scenario-read", { path: request.readPath });
  const output = JSON.stringify(result);
  if (Buffer.byteLength(output) > 131072) throw Error("oversized test read result");
  process.stdout.write(output + "\n");
} else {
  const tools = new Map<string, any>();
  const extension = await import(pathToFileURL(process.argv[2]).href);
  extension.default({ registerTool(tool: any) { tools.set(tool.name, tool); } });
  const tool = tools.get("preview");
  if (!tool || tools.size !== 5 || !tools.has("test")) throw Error("production preview registration missing");
  const result = await tool.execute("scenario-preview", request.params, undefined);
  const output = JSON.stringify(result);
  if (Buffer.byteLength(output) > 131072) throw Error("oversized test tool result");
  process.stdout.write(output + "\n");
}