// @frontmatter:start
// Checks that Agent runtime sources do not retain provider-specific client wiring.
// @frontmatter:end
import Foundation
import Testing

@Test func agentHasNoGenericAgentXPCClientLayout() throws {
	let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
		.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
	let fileManager = FileManager.default
	#expect(
		!fileManager.fileExists(
			atPath: root.appendingPathComponent(
				"Agent/Sources/Application/MacApperAgentXPCLayout.swift"
			).path))
	let runtime = try String(
		contentsOf: root.appendingPathComponent(
			"Agent/Sources/Application/PiRPCProcess.swift"), encoding: .utf8)
	#expect(!runtime.contains("MAC_APPER_AGENT_TERMINAL_CLIENT_PATH"))
	#expect(runtime.contains("_TERMINAL_CLIENT_PATH"))
}

@Test func agentContainsNoBuiltInProviderNames() throws {
	let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
		.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
	for file in ["AgentIntegrationCatalog.swift", "PiRPCProcess.swift"] {
		let source = try String(
			contentsOf: root.appendingPathComponent("Agent/Sources/Application/\(file)"),
			encoding: .utf8)
		#expect(!source.contains("DevToolsXPCClient"))
		#expect(!source.contains("WebXPCClient"))
	}
}
