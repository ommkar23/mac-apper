// @frontmatter:start
// Checks Parallel factory composition and installed Pi loading, exposure, and nested tool selection offline.
// @frontmatter:end
import Foundation
import Testing

private func runParallelExtensionCheck(_ script: String) throws {
	let package = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
		.deletingLastPathComponent().deletingLastPathComponent()
	let process = Process(), output = Pipe()
	process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
	process.arguments = [
		"node", "--no-warnings", "--experimental-vm-modules", "--input-type=module", "-e", script,
		package.appendingPathComponent("Extensions/parallel-codemode.ts").path,
	]
	var environment = ProcessInfo.processInfo.environment
	environment["PI_OFFLINE"] = "1"
	environment["PI_SKIP_VERSION_CHECK"] = "1"
	process.environment = environment
	process.standardOutput = output
	process.standardError = output
	try process.run()
	let data = output.fileHandleForReading.readDataToEndOfFile()
	process.waitUntilExit()
	try #require(
		process.terminationStatus == 0 && data.count <= 65_536,
		"\(String(decoding: data, as: UTF8.self))")
}

@Test func parallelCodemodeExtensionComposesFixedFactoriesWithoutCredentials() throws {
	try runParallelExtensionCheck(
		#"""
		import assert from "node:assert/strict";
		import { readFileSync } from "node:fs";
		import { stripTypeScriptTypes } from "node:module";
		import { pathToFileURL, fileURLToPath } from "node:url";
		import { SourceTextModule, SyntheticModule } from "node:vm";
		const url = pathToFileURL(process.argv[1]).href;
		const source = readFileSync(process.argv[1], "utf8");
		const calls = [];
		const pi = Object.freeze({ marker: "registration API" });
		const mock = new SyntheticModule(["createCodemodeExtension", "createMcpExtension"], function () {
		  for (const name of ["createCodemodeExtension", "createMcpExtension"]) {
		    this.setExport(name, (options) => {
		      calls.push({ name, options });
		      return async (api) => {
		        await Promise.resolve();
		        assert.equal(api, pi);
		        calls.push({ invoked: name });
		      };
		    });
		  }
		});
		const urls = new SyntheticModule(["fileURLToPath"], function () {
		  this.setExport("fileURLToPath", fileURLToPath);
		});
		const module = new SourceTextModule(stripTypeScriptTypes(source), {
		  identifier: url, initializeImportMeta(meta) { meta.url = url; },
		});
		await module.link((name) => {
		  if (name === "@earendil-works/pi-coding-agent") return mock;
		  if (name === "node:url") return urls;
		  assert.fail(`Unexpected dependency: ${name}`);
		});
		await module.evaluate();
		await module.namespace.default(pi);
		assert.deepEqual(calls.map(c => c.name ?? c.invoked), [
		  "createCodemodeExtension", "createCodemodeExtension", "createMcpExtension", "createMcpExtension",
		]);
		assert.deepEqual(calls[0].options, { mode: "on", models: false });
		assert.deepEqual(Object.keys(calls[2].options), ["loadConfig"]);
		const loadConfig = calls[2].options.loadConfig;
		const hostileContext = new Proxy({}, { get() { assert.fail("Configuration must not consult context"); } });
		const expected = {
		  servers: [{ name: "parallel", source: process.argv[1], scope: "extension", config: {
		    url: "https://search.parallel.ai/mcp", exposure: "hidden",
		    toolExposure: { web_search: "codemode", web_fetch: "codemode" },
		  }}], errors: [],
		};
		assert.deepEqual(loadConfig(hostileContext), expected);
		const first = loadConfig(hostileContext);
		first.servers[0].config.url = "https://invalid.example/mcp";
		first.servers[0].config.toolExposure.unapproved = "direct";
		assert.deepEqual(loadConfig(hostileContext), expected);
		// Exact config equality rejects credentials, auth/header/env overrides, custom transports and retries.
		assert.doesNotMatch(source, /process\.env|PARALLEL_API_KEY|Bearer\s|createAgentSession|\/Users\//);
		console.log("Mocked composition, fixed configuration, fresh allowlist and credential safety passed");
		"""#)
}

@Test func parallelCodemodeExtensionLoadsWithInstalledPiWithoutStartingASession() throws {
	try runParallelExtensionCheck(
		#"""
		import assert from "node:assert/strict";
		import { execFileSync } from "node:child_process";
		import { existsSync, readFileSync, realpathSync } from "node:fs";
		import { dirname, join } from "node:path";
		import { pathToFileURL } from "node:url";
		let root = dirname(realpathSync(execFileSync("/usr/bin/which", ["pi"], { encoding: "utf8" }).trim()));
		while (!existsSync(join(root, "package.json"))) {
		  assert.notEqual(dirname(root), root, "Cannot locate installed Pi package");
		  root = dirname(root);
		}
		const manifest = JSON.parse(readFileSync(join(root, "package.json"), "utf8"));
		assert.equal(manifest.name, "@earendil-works/pi-coding-agent");
		const imported = await import(pathToFileURL(join(root, "dist/index.js")));
		assert.equal(typeof imported.createMcpExtension, "function");
		assert.equal(typeof imported.createCodemodeExtension, "function");
		const { loadExtensions } = await import(pathToFileURL(join(root, "dist/core/extensions/loader.js")));
		// Only factories execute. Never emit session_start, execute tools or create an AgentSession.
		const loaded = await loadExtensions([process.argv[1]], dirname(process.argv[1]));
		assert.deepEqual(loaded.errors, []);
		assert.equal(loaded.extensions.length, 1);
		const extension = loaded.extensions[0];
		assert.deepEqual([...extension.tools.keys()], ["codemode"]);
		assert.ok(extension.commands.has("mcp"));
		assert.ok(extension.handlers.has("session_start"));
		const { createMcpToolName } = await import(pathToFileURL(join(root, "dist/extensions/mcp/tools.js")));
		const { getMcpToolExposure } = await import(pathToFileURL(join(root, "dist/core/mcp-servers.js")));
		const config = { exposure: "hidden", toolExposure: { web_search: "codemode", web_fetch: "codemode" } };
		for (const name of ["web_search", "web_fetch"]) {
		  assert.equal(createMcpToolName("parallel", name), `mcp__parallel__${name}`);
		  assert.equal(getMcpToolExposure(config, name), "codemode");
		}
		for (const name of ["search", "fetch", "web_search_extra", "unapproved", "*"]) {
		  assert.equal(getMcpToolExposure(config, name), "hidden");
		}
		const { parseArgs } = await import(pathToFileURL(join(root, "dist/cli/args.js")));
		const { AgentSession } = await import(pathToFileURL(join(root, "dist/core/agent-session.js")));
		const { createAllToolDefinitions } = await import(pathToFileURL(join(root, "dist/core/tools/index.js")));
		const { createToolNameMatcher } = await import(pathToFileURL(join(root, "dist/core/mcp-servers.js")));
		const { toToolExposure } = await import(pathToFileURL(join(root, "dist/extensions/mcp/tools.js")));
		const args = parseArgs(["--mode", "rpc", "--no-extensions", "--extension", process.argv[1],
		  "--tools", "codemode", "--no-skills", "--no-prompt-templates", "--no-context-files"]);
		assert.deepEqual(args.diagnostics, []);
		assert.equal(args.mode, "rpc");
		assert.deepEqual(args.tools, ["codemode"]);
		assert.deepEqual(args.extensions, [process.argv[1]]);
		assert.equal(args.noExtensions, true);
		// Execute installed registry/loadout methods on plain fixture state, NOT a constructed
		// AgentSession or SDK bootstrap. No session_start, credentials, transport or tool execution.
		// Supply only the read-only settings accessor needed by prepareLoadout. All action
		// methods retain the loader's throwing stubs; even inherited mode:only cannot override on.
		loaded.runtime.getSettings = () => ({ codemode: { mode: "only" } });
		const fixture = Object.create(AgentSession.prototype);
		const builtins = createAllToolDefinitions(dirname(process.argv[1]));
		const registered = [...extension.tools.values()];
		for (const raw of ["web_search", "web_fetch", "unapproved"]) {
		  registered.push({ sourceInfo: extension.sourceInfo, definition: {
		    name: createMcpToolName("parallel", raw), label: raw, description: "Offline schema fixture",
		    exposure: toToolExposure(getMcpToolExposure(config, raw)), parameters: { type: "object" },
		    execute() { assert.fail("Fixture tool must never execute"); },
		  }});
		}
		Object.assign(fixture, {
		  agent: { state: { tools: [] } },
		  _allowedTools: createToolNameMatcher(args.tools), _allowlistFiltersMcp: false,
		  _baseToolDefinitions: new Map(Object.entries(builtins)),
		  _customTools: [], _toolRegistry: new Map(), _toolDefinitions: new Map(),
		  _pendingToolNames: new Set(),
		  _extensionRunner: {
		    getAllRegisteredTools: () => registered,
		    emitError(error) { assert.fail(JSON.stringify(error)); },
		    createToolContext() { assert.fail("No tool execution context allowed"); },
		  },
		  _rebuildSystemPrompt() {}, // Registry-only check, without session/transcript infrastructure.
		});
		const callable = ["mcp__parallel__web_fetch", "mcp__parallel__web_search"];
		for (const activeToolNames of [args.tools, [...Object.keys(builtins), ...callable, "codemode"]]) {
		  fixture._refreshToolRegistry({ activeToolNames });
		  assert.deepEqual(fixture.getActiveToolNames(), ["codemode"]);
		  assert.deepEqual([...fixture._hiddenDeclarations], []);
		  assert.deepEqual(fixture.getCallableToolNames().sort(), callable);
		  for (const name of Object.keys(builtins)) {
		    assert.equal(fixture._toolRegistry.has(name), false, `${name} must not be registered`);
		    assert.equal(fixture._isAllowedTool(name), false);
		  }
		  assert.equal(fixture._toolRegistry.has("tool_search"), false);
		  assert.ok(fixture._toolRegistry.has("mcp__parallel__unapproved"));
		  assert.equal(fixture._getToolExposure("mcp__parallel__unapproved"), "hidden");
		  assert.doesNotMatch(fixture.agent.state.tools[0].description, /tools\.(read|bash|edit|write|grep|find|ls)\(|`models`/);
		}
		console.log(`Installed Pi ${manifest.version}: CLI loader, static exposure and registry checks passed; no session started`);
		"""#)
}
