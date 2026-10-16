// @frontmatter:start
// Checks Chat's actual declaration inventory, lightweight discovery and selector rejection offline.
// @frontmatter:end
import Foundation
import Scenario
import Testing

@Suite @MainActor struct ChatContractTests {
	@Test func actualInventoryIsLightweightAndOrdered() throws {
		let registry = try ScenarioRegistry([chatCollection()])
		#expect(registry.collectionNames == ["agent-chat"])
		#expect(
			registry.caseNames == [
				"chat-model-greeting", "country-news-japan", "chat-follow-up", "chat-disconnect-replay",
				"chat-resume", "chat-session-isolation", "chat-abort-reuse", "chat-capabilities",
			])
		#expect(registry.caseNames == ChatModelCases.names)
		let context = ChatCollection()
		#expect(context.contexts.isEmpty)
		#expect(ChatCaseContext().sessions.owned.isEmpty)
	}

	@Test func selectorRejectsUnknownBeforeAcquisition() throws {
		#expect(throws: ScenarioFailure.self) { try validateChatSelector("not-a-chat-case") }
		try validateChatSelector(nil)
		for name in ChatModelCases.names { try validateChatSelector(name) }
	}

	@Test func declarationsUseNamedObservedPhases() throws {
		let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
		let entry = try String(
			contentsOf: directory.appendingPathComponent("ChatTests.swift"), encoding: .utf8)
		#expect(
			!FileManager.default.fileExists(
				atPath: directory.appendingPathComponent("CountryNewsScenarioTests.swift").path))
		#expect(!entry.contains("registry.runCase"))
		#expect(!entry.contains("ChatModelCases.run"))
		for required in [
			"ScenarioTestingObserver()", "requireSuccess()", "timeoutSeconds: 2100",
			"prepare production Chat test host", "validate hosted Chat execution",
			"ChatScenarioCleanup.finishHost",
		] {
			#expect(entry.contains(required))
		}
	}
}
