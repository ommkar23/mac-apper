// @frontmatter:start
// Verifies Create's scoped signed Agent/DevTools host and private workspace without Pi startup or live calls.
// @frontmatter:end
import AgentMacosClient
import AgentMacosClientModel
import Foundation
import Scenario
import Testing

@Test @MainActor func createCredentialSnapshotOffline() throws {
	let now = Date(timeIntervalSince1970: 1_000_000)
	let entry: [String: Any] = [
		"type": "oauth", "access": "synthetic-access", "refresh": "must-not-copy",
		"expires": (now.timeIntervalSince1970 + 1600) * 1000, "accountId": "synthetic-account",
		"unrelated": "must-not-copy",
	]
	let snapshot = try CreateScenarioIsolation.credentialSnapshot(entry, now: now)
	#expect(snapshot["refresh"] as? String == "")
	#expect(snapshot["access"] as? String == "synthetic-access")
	#expect(snapshot["unrelated"] == nil)
	#expect(throws: (any Error).self) {
		try CreateScenarioIsolation.credentialSnapshot(entry, now: now.addingTimeInterval(101))
	}
}

@Test @MainActor func createIsolatedHostOffline() async throws {
	if ProcessInfo.processInfo.environment["AGENT_CREATE_OFFLINE_HOST"] == "1" {
		let home = try CreateScenarioIsolation.requireHome()
		let app = Bundle.main.bundleURL
		for relative in [
			"Contents/XPCServices/AgentXPCService.xpc",
			"Contents/Applications/DevTools.app/Contents/XPCServices/DevToolsApplication.xpc",
		] {
			let data = try Data(contentsOf: app.appendingPathComponent(relative + "/Contents/Info.plist"))
			let info = try #require(
				PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
			let xpc = try #require(info["XPCService"] as? [String: Any])
			let environment = try #require(xpc["EnvironmentVariables"] as? [String: String])
			#expect(environment["HOME"] == home.path && environment["CFFIXED_USER_HOME"] == home.path)
		}
		let adapter = AgentServiceXPCAdapter()
		let workspace = WorkspaceSession(
			runtime: AgentXPCRuntime(transport: adapter),
			workspaceStore: AgentXPCWorkspaceStore(transport: adapter))
		await workspace.refreshLibrary()
		try #require(
			workspace.library.allSatisfy {
				$0.isChatOnly && $0.sessions.isEmpty
					&& $0.project.deletingLastPathComponent().resolvingSymlinksInPath()
						== home.appendingPathComponent(".mac-apper").resolvingSymlinksInPath()
			})
		let prepared = try await AgentXPCWorkspaceStore(transport: adapter).prepareCreateProject(
			request: "No-model Create isolation preflight")
		try #require(
			prepared.project.deletingLastPathComponent().resolvingSymlinksInPath()
				== home.appendingPathComponent(".mac-apper").resolvingSymlinksInPath())
		try #require(!FileManager.default.fileExists(atPath: prepared.sessionFile.path))
		let project = try #require(UUID(uuidString: prepared.project.lastPathComponent))
		let session = UUID().uuidString
		let requestID = UUID().uuidString
		let payload = try JSONSerialization.data(withJSONObject: [
			"projectRoot": prepared.project.path, "action": "add_plan",
		])
		let request = try JSONSerialization.data(withJSONObject: [
			"version": 1, "requestID": requestID, "projectID": project.uuidString, "sessionID": session,
			"command": "plan", "payload": payload.base64EncodedString(),
		])
		let reply = try XPCClientAdapter().call(
			app.appendingPathComponent(
				"Contents/Applications/DevTools.app/Contents/MacOS/DevToolsTerminalClient"),
			request: request,
			environment: ["OPENXPC_PROJECT_ID": project.uuidString, "OPENXPC_SESSION_ID": session])
		try #require(reply.status == 0)
		let record = try #require(JSONSerialization.jsonObject(with: reply.data) as? [String: Any])
		try #require(record["success"] as? Bool == true && record["requestID"] as? String == requestID)
		print(
			"CREATE_OFFLINE_ISOLATION: native Agent project and generated DevTools plan succeeded without Pi"
		)
	} else {
		let home = try IsolatedScenarioHome()
		try home.linkInstalledToolchain()
		_ = try home.privateDirectory(".mac-apper")
		_ = try home.privateDirectory(".pi/agent")
		let host = try AgentChatScenarioInputs.prepareHost(includeDevTools: true, isolatedHome: home)
		var passed = false
		defer {
			do {
				try stopScaffoldService(
					host.app, relative: "AgentXPCService.xpc/Contents/MacOS/AgentApplication")
				try stopScaffoldService(
					host.app?.appendingPathComponent("Contents/Applications/DevTools.app"),
					relative: "DevToolsApplication.xpc/Contents/MacOS/DevToolsApplication")
				if passed {
					try host.remove(); try home.remove(cleanupConfirmed: true)
				} else {
					print(
						"CREATE_OFFLINE_RETAINED: \(host.app?.path ?? "unavailable") \(home.directory.path)")
				}
			} catch { Issue.record("Offline isolation cleanup failed; retain host/home: \(error)") }
		}
		let result = try host.runTest(
			filter: "^AgentScenarioTests.createIsolatedHostOffline",
			environment: home.environment.merging([
				"AGENT_CREATE_OFFLINE_HOST": "1", "AGENT_CREATE_HOME": home.directory.path,
			]) { _, value in value }, timeoutSeconds: 90)
		print(result.output)
		passed = result.status == 0 && result.output.contains("Test createIsolatedHostOffline() passed")
		try #require(passed)
	}
}
