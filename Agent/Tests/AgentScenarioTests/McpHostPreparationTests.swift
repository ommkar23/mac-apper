// @frontmatter:start
// Verifies signed Chat host preparation stages authored MCP/codemode resources without Web, Pi startup, or live calls.
// @frontmatter:end
import Foundation
import Testing

@Test @MainActor func agentMcpHostPreparationOffline() throws {
	let host = try AgentChatScenarioInputs.prepareHost()
	defer {
		do {
			try stopScaffoldService(
				host.app, relative: "AgentXPCService.xpc/Contents/MacOS/AgentApplication")
			try host.remove()
		} catch { Issue.record("Offline MCP host cleanup failed; retain host: \(error)") }
	}
	let app = try #require(host.app)
	let resources = app.appendingPathComponent("Contents/Resources")
	let package = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
		.deletingLastPathComponent().deletingLastPathComponent()
	for file in [
		"parallel-codemode.ts", "create-instructions.ts", "name-and-rename.ts", "create-app.ts",
	] {
		#expect(
			try Data(contentsOf: resources.appendingPathComponent("AgentExtensions/\(file)"))
				== Data(contentsOf: package.appendingPathComponent("Extensions/\(file)")))
	}
	let catalog = try #require(
		JSONSerialization.jsonObject(
			with: Data(contentsOf: resources.appendingPathComponent("IntegrationCatalog.json")))
			as? [String: Any])
	let apps = try #require(catalog["apps"] as? [[String: Any]])
	#expect(!apps.contains { $0["id"] as? String == "web" })
	#expect(
		!FileManager.default.fileExists(
			atPath: app.appendingPathComponent("Contents/Applications/Web.app").path))
	#expect(
		!FileManager.default.fileExists(
			atPath: app.appendingPathComponent("Contents/Applications/DevTools.app").path))
	print(
		"MCP_HOST_OFFLINE: signed Agent-only host; exact authored extension bytes; no Pi session_start")
}
