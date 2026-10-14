// @frontmatter:start
// Tests the deployed Agent runtime's explicit provider, model, and thinking launch arguments.
// @frontmatter:end
import Foundation
import Scenario
import Testing
@testable import AgentApplication

@Test @MainActor func deployedAgentPinsRequestedModelAndThinking() async throws {
	let root = try ProjectTemporaryDirectory.root().appendingPathComponent(UUID().uuidString)
	try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
	defer { try? FileManager.default.removeItem(at: root) }
	let executable = root.appendingPathComponent("fixture-pi")
	try
		"#!/bin/sh\nprintf '%s\\n' \"$@\" > arguments.txt\nwhile IFS= read -r line; do printf '%s\\n' '{\"type\":\"agent_end\"}'; done\n"
		.write(to: executable, atomically: true, encoding: .utf8)
	try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
	let config = AgentXPCServiceMain.processConfiguration(executable: executable)
	#expect(config.provider == "openai-codex")
	#expect(config.model == "gpt-6.1-sol")
	#expect(config.thinking == "medium")
	let catalogFile = root.appendingPathComponent("catalog.json")
	try Data(
		"{\"schemaVersion\":1,\"apps\":[{\"id\":\"web\",\"packagePath\":\"web\",\"application\":{\"bundleName\":\"Web.app\",\"executableProduct\":\"WebAgentClient\",\"infoPlist\":\"Info.plist\"},\"piExtensions\":[]}]}"
			.utf8
	).write(to: catalogFile)
	let extensions = root.appendingPathComponent("Resources/AgentExtensions")
	try FileManager.default.createDirectory(at: extensions, withIntermediateDirectories: true)
	try Data().write(to: extensions.appendingPathComponent("parallel-codemode.ts"))
	let runtime = PiRPCProcess(
		configuration: config,
		integrationCatalog: try AgentIntegrationCatalog.load(from: catalogFile),
		integrationRootURL: root)
	_ = try await runtime.start(
		agentID: "chat", in: root,
		sessionFile: root.appendingPathComponent(".pi/sessions/\(UUID().uuidString).jsonl"), title: nil,
		firstRequest: false)
	try await runtime.prompt("fixture")
	let captured = root.appendingPathComponent("arguments.txt")
	for _ in 0..<100 where !FileManager.default.fileExists(atPath: captured.path) {
		try await Task.sleep(for: .milliseconds(10))
	}
	let arguments = try String(contentsOf: captured, encoding: .utf8)
	#expect(arguments.contains("--provider\nopenai-codex"))
	#expect(arguments.contains("--model\ngpt-6.1-sol"))
	#expect(arguments.contains("--thinking\nmedium"))
	#expect(await runtime.stop())
}
