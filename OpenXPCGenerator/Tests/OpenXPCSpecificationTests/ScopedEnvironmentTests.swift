import Foundation
import Scenario
import OpenXPCSpecification
import Testing

@Test func generatedPiClientPreservesScopedHomeEnvironment() throws {
	let spec = try OpenXPCSpecification(
		yaml: """
			service:
			  identifier: com.example.environment
			  target: EnvironmentService
			  generate: service
			types:
			  - name: Input
			    fields: []
			  - name: Output
			    fields:
			      - { name: content, type: string, maxLength: 4096 }
			operations:
			  - name: ping
			    request: Input
			    response: Output
			    tool:
			      label: Ping
			      description: Check environment.
			clients:
			  - target: EnvironmentClient
			    generate: agentClient
			    operations: [ping]
			""")
	let source = try #require(
		OpenXPCSourceGenerator.generate(spec: spec, target: "EnvironmentClient").piExtension)
	let root = try ProjectTemporaryDirectory.root().appendingPathComponent(UUID().uuidString)
	try FileManager.default.createDirectory(
		at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
	defer { try? FileManager.default.removeItem(at: root) }
	let script = root.appendingPathComponent("environment.ts")
	// Observe the real generated call and tool registration without replacing its framing or error handler.
	let harness = #"""
		import { strict as assert } from "node:assert";
		import childProcess from "node:child_process";
		import { syncBuiltinESMExports } from "node:module";
		import { EventEmitter } from "node:events";
		let expected: Record<string, string> = {};
		let fail = false;
		let expectedPayload: Record<string, unknown> = {};
		childProcess.spawn = ((executable: string, args: string[], options: any) => {
		  assert.equal(executable, "/owned/client"); assert.deepEqual(args, []);
		  assert.equal(options.shell, false); assert.deepEqual(options.stdio, ["pipe", "pipe", "pipe"]);
		  assert.deepEqual(options.env, expected);
		  const child: any = new EventEmitter();
		  child.stdout = new EventEmitter(); child.stderr = new EventEmitter(); child.kill = () => true;
		  child.stdin = new EventEmitter();
		  child.stdin.end = (record: string) => {
		    assert.equal(record.split("\n").length, 2); assert.ok(record.endsWith("\n"));
		    const request = JSON.parse(record);
		    assert.deepEqual(Object.keys(request).sort(), ["command", "payload", "projectID", "requestID", "sessionID", "version"]);
		    assert.equal(request.version, 1); assert.equal(request.command, "ping");
		    assert.equal(request.projectID, expected.OPENXPC_PROJECT_ID);
		    assert.equal(request.sessionID, expected.OPENXPC_SESSION_ID);
		    assert.match(request.requestID, /^[0-9a-f-]{36}$/);
		    assert.deepEqual(JSON.parse(Buffer.from(request.payload, "base64").toString()), expectedPayload);
		    queueMicrotask(() => {
		      child.stdout.emit("data", JSON.stringify({version: 1, requestID: request.requestID, projectID: request.projectID,
		        success: true, payload: Buffer.from(JSON.stringify({content: "pong"})).toString("base64")}) + "\n");
		      child.emit("exit", fail ? 1 : 0);
		    });
		  };
		  return child;
		}) as any;
		syncBuiltinESMExports();
		const {default: register} = await import("./extension.ts");
		let tool: any;
		register({registerTool(value: any) {tool = value;}} as any);
		process.env.OPENXPC_ENVIRONMENTCLIENT_CLIENT_PATH = "/owned/client";
		process.env.OPENXPC_PROJECT_ID = "12345678-1234-1234-1234-123456789abc";
		process.env.OPENXPC_SESSION_ID = "22345678-1234-1234-1234-123456789abc";
		process.env.OPENXPC_PROJECT_ROOT = "/not-forwarded";
		process.env.SECRET_SENTINEL = "must-not-inherit";
		for (const values of [{HOME: "/private/home", CFFIXED_USER_HOME: "/private/fixed", TMPDIR: "/private/tmp/"}, {}, {HOME: ""}]) {
		  for (const key of ["HOME", "CFFIXED_USER_HOME", "TMPDIR"]) delete process.env[key];
		  Object.assign(process.env, values);
		  expected = {...values, OPENXPC_PROJECT_ID: process.env.OPENXPC_PROJECT_ID!, OPENXPC_SESSION_ID: process.env.OPENXPC_SESSION_ID!};
		  const result = await tool.execute("tool-id", {}, undefined);
		  assert.deepEqual(result, {content: [{type: "text", text: "pong"}], details: {result: {content: "pong"}}});
		}
		expectedPayload = {projectID: "caller-project", sessionID: "caller-session", OPENXPC_PROJECT_ID: "caller-env"};
		assert.equal((await tool.execute("tool-id", expectedPayload, undefined)).content[0].text, "pong");
		expectedPayload = {};
		fail = true;
		assert.deepEqual(await tool.execute("tool-id", {}, undefined), {content: [{type: "text", text: "Error: Client failed."}], details: {}, isError: true});
		console.log("scoped-environment-passed");
		"""#
	try source.write(
		to: root.appendingPathComponent("extension.ts"), atomically: true, encoding: .utf8)
	try harness.write(to: script, atomically: true, encoding: .utf8)
	let process = Process()
	process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
	process.arguments = ["node", "--experimental-strip-types", script.path]
	let output = Pipe()
	process.standardOutput = output
	process.standardError = output
	try process.run()
	let diagnostics = String(
		decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
	process.waitUntilExit()
	#expect(process.terminationStatus == 0, "\(diagnostics)")
	#expect(diagnostics.contains("scoped-environment-passed"))
}
