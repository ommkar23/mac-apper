// @frontmatter:start
// Declares the opt-in Chat collection and observed signed-host preparation, validation and gated cleanup phases.
// @frontmatter:end
import Foundation
import Scenario
import ScenarioTesting
import Testing

@MainActor func chatCases() -> [ScenarioCase<ChatCollection>] {
	[
		ChatModelCases.greetingCase(), ChatModelCases.countryNewsCase(),
		ChatModelCases.followUpCase(), ChatModelCases.disconnectReplayCase(),
		ChatModelCases.resumeCase(), ChatModelCases.isolationCase(),
		ChatModelCases.abortReuseCase(), ChatModelCases.capabilitiesCase(),
	]
}

@MainActor func chatCollection() -> ScenarioCollection {
	ScenarioCollection(
		"agent-chat", context: ChatCollection.init, setup: [], cases: chatCases(),
		cleanup: [
			ChatCollection.confirmationChain()
		])
}

@MainActor func validateChatSelector(_ selected: String?) throws {
	if let selected, !chatCases().map(\.name).contains(selected) {
		throw ScenarioFailure.message("unknown Agent scenario case")
	}
}

@MainActor private final class ChatHostContext: CaseContext {
	var host: PackagedTestHost?
	var app: URL?
	var result: PackagedTestHost.Result?
}

@MainActor private func chatHostCollection() -> ScenarioCollection {
	ScenarioCollection(
		"chat-host", context: ChatCollection.init, setup: [],
		cases: [
			ScenarioCase(
				"chat-host-execution", context: { _ in ChatHostContext() },
				setup: [
					Step("prepare production Chat test host") { context in
						let host = try AgentChatScenarioInputs.prepareHost()
						context.host = host
						context.app = host.app
						print("CHAT_HOST: \(try #require(context.app).path)")
					}
				],
				behaviour: [
					Step("execute bounded hosted Chat selection") { context in
						let host = try #require(context.host)
						context.result = try host.runTest(
							filter: "^AgentScenarioTests.agentChatScenarios",
							environment: ["AGENT_SCENARIO_TEST_HOST": "1"], timeoutSeconds: 2100)
						print(try #require(context.result).output)
					},
					Step("validate hosted Chat execution") { context in
						let result = try #require(context.result)
						try #require(
							result.output.contains("Test agentChatScenarios() started."),
							"Packaged loader did not execute the scenario test")
						try #require(
							result.status == 0,
							"Packaged client-model scenarios failed; see case diagnostics above")
					},
				],
				cleanup: [
					CleanupChain(
						"gate Chat host cleanup on inner confirmation",
						steps: [
							Step("finish exact-owned Chat host or retain it") { context in
								guard
									let host = context.host
								else { return }
								do {
									try ChatScenarioCleanup.finishHost(
										cleanupConfirmed: context.result?.output.split(separator: "\n").contains {
											$0 == ChatScenarioCleanup.confirmation
										} == true, passed: context.result?.status == 0,
										stop: {
											try stopScaffoldService(
												host.app,
												relative: "AgentXPCService.xpc/Contents/MacOS/AgentApplication")
										}, remove: { try host.remove() })
									print("CHAT_HOST_CLEANUP: removed \(context.app?.path ?? "unknown")")
								} catch {
									print("CHAT_HOST_RETAINED: \(context.app?.path ?? "unknown"); \(error)")
									throw error
								}
							}
						])
				])
		])
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["AGENT_SCENARIO_LIVE"] == "1"))
@MainActor func agentChatScenarios() async throws {
	let environment = ProcessInfo.processInfo.environment
	let selected = environment["AGENT_SCENARIO_CASE"]
	try validateChatSelector(selected)
	let observer = ScenarioTestingObserver()
	if environment["AGENT_SCENARIO_TEST_HOST"] == "1" {
		_ = try ChatModelCases.serviceIdentifier()
		let registry = try ScenarioRegistry([chatCollection()])
		let report: ScenarioReport
		if let selected {
			report = try await registry.executeCase(selected, observer: observer)
		} else {
			report = try await registry.executeCollection("agent-chat", observer: observer)
		}
		try report.requireSuccess()
	} else {
		let registry = try ScenarioRegistry([chatHostCollection()])
		try await registry.executeCollection("chat-host", observer: observer).requireSuccess()
	}
}
