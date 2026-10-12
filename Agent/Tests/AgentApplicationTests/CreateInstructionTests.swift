// @frontmatter:start
// Executes the authored Create prompt hooks without model calls and checks prompt composition across first and later requests.
// @frontmatter:end
import Foundation
import Testing

@Test func createInstructionHookPreservesBasePromptAndComposesFirstRequestNaming() throws {
	let package = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
		.deletingLastPathComponent().deletingLastPathComponent()
	let extensions = package.appendingPathComponent("Extensions")
	let script = #"""
		import assert from "node:assert/strict";
		const { default: instructions, createInstructions } = await import(process.argv[1]);
		const { default: naming } = await import(process.argv[2]);
		const base = "BASE SYSTEM\nTOOLS";
		async function prompt(first) {
		  const handlers = [];
		  const pi = { on(name, handler) {
		    assert.equal(name, "before_agent_start"); handlers.push(handler);
		  }};
		  instructions(pi);
		  if (first) naming(pi);
		  let systemPrompt = base;
		  for (const handler of handlers) {
		    const result = await handler({ systemPrompt });
		    systemPrompt = result.systemPrompt;
		  }
		  return systemPrompt;
		}
		console.log(JSON.stringify({ instructions: createInstructions,
		  first: await prompt(true), later: await prompt(false), again: await prompt(false) }));
		"""#
	let process = Process(), output = Pipe()
	process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
	process.arguments = [
		"node", "--no-warnings", "--experimental-strip-types", "--input-type=module", "-e", script,
		extensions.appendingPathComponent("create-instructions.ts").absoluteString,
		extensions.appendingPathComponent("create-app.ts").absoluteString,
	]
	process.standardOutput = output
	process.standardError = output
	try process.run()
	let data = output.fileHandleForReading.readDataToEndOfFile()
	process.waitUntilExit()
	try #require(
		process.terminationStatus == 0 && data.count <= 65_536,
		"\(String(decoding: data, as: UTF8.self))")
	let result = try #require(JSONSerialization.jsonObject(with: data) as? [String: String])
	let instructions = try #require(result["instructions"])
	let later = try #require(result["later"])
	#expect(later == "BASE SYSTEM\nTOOLS\n\n" + instructions)
	#expect(result["again"] == later)
	#expect(result["first"]?.hasPrefix(later + "\n\n") == true)
	#expect(result["first"]?.contains("call set_app_name exactly once") == true)
	#expect(!later.contains("This is the first request"))
	for requirement in [
		"Model–View", "@Observable", "@Bindable", "business logic out of views",
		"Sources/AppModel/ApplicationModel.swift", "Sources/AppViews/ApplicationRoot.swift",
		"Tests/AppModelTests", "protected", "plan", "preview", "build", "run", "web_search/web_fetch",
		"codemode", "artifact.reviewPath", "optional", "text only",
		"does not prove image inspection",
		"development launch is not production packaging", "Core Data", "ApplicationState",
		"ApplicationPersistence.makeSchema", "NSManagedObject", "migration is disabled",
		"in-memory", "offline-first", "Do not use @Query", "sync", "Use test to run",
		"status passed", "@NSManaged", "NSEntityDescription", "explicit class/entity names",
		"production(appID:)", "default initializer", "CoreData/data.sqlite", "Stable app UUID",
		"refresh ApplicationState", "success or failure", "Never silently fall back to memory",
		"Close test stores before removing fixtures", "never reset or convert stores",
	] {
		#expect(instructions.contains(requirement), "Missing Create guidance: \(requirement)")
	}
}
