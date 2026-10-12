// @frontmatter:start
// Runs eight opt-in Agent client-model/MCP scenarios in a minimal signed test host with exact-owned service cleanup.
// @frontmatter:end
import Foundation
import Scenario
import Testing

@MainActor private final class ChatCollection: CollectionContext {}

@MainActor private func chatCases() -> [ScenarioCase<ChatCollection>] {
	ChatModelCases.names.map { name in
		ScenarioCase(
			name, context: { _ in ChatModelSessions() },
			steps: [
				Step("drive the production MacOS client model and assert \(name)") { sessions in
					try await withThrowingTaskGroup(of: Void.self) { group in
						group.addTask { try await ChatModelCases.run(name, sessions: sessions) }
						group.addTask {
							try await Task.sleep(for: .seconds(220))
							throw ScenarioFailure.message("\(name) execution deadline exceeded")
						}
						defer { group.cancelAll() }
						try await group.next()
					}
				}
			], teardown: { try await $0.cleanup() })
	}
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["AGENT_SCENARIO_LIVE"] == "1"))
@MainActor func agentChatScenarios() async throws {
	let environment = ProcessInfo.processInfo.environment
	let selected = environment["AGENT_SCENARIO_CASE"]
	if let selected, !ChatModelCases.names.contains(selected) {
		throw ScenarioFailure.message("unknown Agent scenario case")
	}
	if environment["AGENT_SCENARIO_TEST_HOST"] == "1" {
		_ = try ChatModelCases.serviceIdentifier()
		let collection = ScenarioCollection(
			"agent-chat", context: ChatCollection.init, cases: chatCases())
		let registry = try ScenarioRegistry([collection])
		if let selected {
			try await registry.runCase(selected)
		} else {
			try await registry.runCollection("agent-chat")
		}
	} else {
		let host = try AgentChatScenarioInputs.prepareHost()
		let app = try #require(host.app)
		print("CHAT_HOST: \(app.path)")
		let result: PackagedTestHost.Result
		do {
			result = try host.runTest(
				filter: "^AgentScenarioTests.agentChatScenarios",
				environment: ["AGENT_SCENARIO_TEST_HOST": "1"])
		} catch {
			print("CHAT_HOST_RETAINED: \(app.path); hosted execution/cleanup unconfirmed: \(error)")
			throw error
		}
		print(result.output)
		do {
			try ChatScenarioCleanup.finishHost(
				cleanupConfirmed: result.output.split(separator: "\n").contains {
					$0 == ChatScenarioCleanup.confirmation
				}, passed: result.status == 0,
				stop: {
					try stopScaffoldService(
						host.app, relative: "AgentXPCService.xpc/Contents/MacOS/AgentApplication")
				}, remove: { try host.remove() })
			print("CHAT_HOST_CLEANUP: removed \(app.path)")
		} catch {
			print("CHAT_HOST_RETAINED: \(app.path); \(error)")
			throw error
		}
		try #require(
			result.output.contains("Test agentChatScenarios() started."),
			"Packaged loader did not execute the scenario test")
		try #require(
			result.status == 0, "Packaged client-model scenarios failed; see case diagnostics above")
	}
}
