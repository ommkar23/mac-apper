// Test-only observation. The generated extension and terminal client remain unchanged.
import childProcess from "node:child_process";
import { syncBuiltinESMExports } from "node:module";
import { pathToFileURL } from "node:url";

const limit = 131072;
export function observeSpawn(real: any, records: any[]) {
  return (executable: any, args: any, options: any) => {
    const child = real(executable, args, options); // Forward the exact objects, without replacement options.
    const record: any = { executable, args, options, stdin: "", stdout: "", stderr: "", closed: false, fault: false };
    record.done = new Promise(resolve => child.once("close", (code: any, signal: any) => {
      record.closed = true; record.code = code; record.signal = signal; resolve(undefined);
    }));
    records.push(record);
    const append = (key: string, chunk: any, encoding?: any) => {
      if (chunk === undefined || chunk === null || typeof chunk === "function") return;
      const bytes = Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk, encoding || "utf8");
      if (Buffer.byteLength(record[key]) + bytes.length > limit) record.fault = true;
      else record[key] += bytes.toString("utf8");
    };
    for (const key of ["stdout", "stderr"]) child[key].on("data", (chunk: any) => append(key, chunk));
    for (const key of ["write", "end"]) {
      const original = child.stdin[key];
      child.stdin[key] = function (...values: any[]) {
        append("stdin", values[0], typeof values[1] === "string" ? values[1] : undefined);
        return original.apply(this, values);
      };
    }
    child.on("error", () => { record.fault = true; });
    child.stdin.on("error", () => { record.fault = true; });
    return child;
  };
}
function envelope(text: string) {
  if (!text.endsWith("\n") || text.slice(0, -1).includes("\n") || Buffer.byteLength(text) > limit) throw Error("uncertain framing");
  const value = JSON.parse(text.slice(0, -1));
  if (!value || Array.isArray(value) || typeof value !== "object") throw Error("uncertain envelope");
  return value;
}
function payload(encoded: any) {
  if (typeof encoded !== "string") throw Error("missing payload");
  const bytes = Buffer.from(encoded, "base64");
  if (bytes.toString("base64") !== encoded || bytes.length > 65536) throw Error("invalid payload");
  return JSON.parse(bytes.toString("utf8"));
}
export function classifyObservation(records: any[], bound: any) {
  if (records.length !== 1) throw Error("uncertain spawn count");
  const r = records[0];
  if (r.executable !== bound.executable || r.args.length !== 0 || r.options.shell !== false ||
      JSON.stringify(r.options.stdio) !== JSON.stringify(["pipe", "pipe", "pipe"]) ||
      !r.closed || r.signal !== null || r.fault || r.stderr) throw Error("uncertain child completion");
  const expected = { ...bound.environment, OPENXPC_PROJECT_ID: bound.projectID.toLowerCase(), OPENXPC_SESSION_ID: bound.sessionID.toLowerCase() };
  if (Object.keys(r.options.env).length !== Object.keys(expected).length || Object.entries(expected).some(([key,value]) => r.options.env[key] !== value)) throw Error("unbound child environment");
  const request = envelope(r.stdin), response = envelope(r.stdout);
  if (Object.keys(request).some(key => !["version","requestID","projectID","sessionID","command","payload"].includes(key)) ||
      Object.keys(response).some(key => !["version","requestID","projectID","success","payload","error"].includes(key)) ||
      request.version !== 1 || response.version !== 1 || request.command !== "preview" ||
      typeof request.requestID !== "string" || response.requestID?.toLowerCase() !== request.requestID.toLowerCase() ||
      request.projectID?.toLowerCase() !== bound.projectID.toLowerCase() || response.projectID?.toLowerCase() !== bound.projectID.toLowerCase() ||
      request.sessionID?.toLowerCase() !== bound.sessionID.toLowerCase() || payload(request.payload).projectRoot !== bound.projectRoot) throw Error("uncorrelated wire traffic");
  if (response.success === false && response.error === "operationFailed" && response.payload == null && r.code === 1) return "operationFailed";
  if (response.success !== true || response.error != null || r.code !== 0) throw Error("uncertain transport error");
  const value = payload(response.payload);
  if (!["rendered","error"].includes(value.status) || /cleanupFailed|reapFailed/.test(String(value.summary))) throw Error("uncertain rendering cleanup");
  return "completed";
}
async function main() {
  let input = "";
  for await (const chunk of process.stdin) {
    input += chunk.toString();
    if (Buffer.byteLength(input) > 16384) throw Error("oversized test request");
  }
  const request = JSON.parse(input);
  let result: any, observation: any, evidence: any;
  if (request.readPath !== undefined) {
    const modulePath = process.env.DEV_TOOLS_SCENARIO_PI_READ_MODULE;
    if (!modulePath?.startsWith("/")) throw Error("installed production read module required");
    const { createReadToolDefinition } = await import(pathToFileURL(modulePath).href);
    result = await createReadToolDefinition(process.env.OPENXPC_PROJECT_ROOT).execute("scenario-read", { path: request.readPath });
  } else {
    const records: any[] = [], tools = new Map<string, any>();
    const real = childProcess.spawn;
    childProcess.spawn = observeSpawn(real, records);
    syncBuiltinESMExports();
    try {
      const extension = await import(pathToFileURL(process.argv[2]).href);
      extension.default({ registerTool(tool: any) {
        if (tools.has(tool.name)) throw Error("production preview registration missing: duplicate tool");
        tools.set(tool.name, tool);
      } });
      const canonicalTools = ["set_app_name", "build", "test", "run", "preview", "plan"];
      const tool = tools.get("preview");
      if (!tool || tools.size !== canonicalTools.length || canonicalTools.some(name => !tools.has(name))) {
        throw Error("production preview registration missing");
      }
      result = await tool.execute("scenario-preview", request.params, undefined);
      await Promise.all(records.map(record => record.done)); // Exit is not close.
      const environment: any = {};
      for (const key of ["HOME","CFFIXED_USER_HOME","TMPDIR"]) if (process.env[key] !== undefined) environment[key] = process.env[key];
      observation = classifyObservation(records, { executable: process.env.OPENXPC_DEVTOOLSTERMINALCLIENT_CLIENT_PATH,
        projectID: process.env.OPENXPC_PROJECT_ID, sessionID: process.env.OPENXPC_SESSION_ID,
        projectRoot: process.env.OPENXPC_PROJECT_ROOT, environment });
      const r = records[0], wire = envelope(r.stdin);
      evidence = { executable: r.executable, requestID: wire.requestID, projectID: wire.projectID,
        sessionID: wire.sessionID, closed: r.closed, code: r.code, completion: observation };
    } finally {
      childProcess.spawn = real; syncBuiltinESMExports();
    }
  }
  const output = JSON.stringify({ result, observation, evidence });
  if (Buffer.byteLength(output) > limit) throw Error("oversized test result");
  process.stdout.write(output + "\n");
}
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) await main();
