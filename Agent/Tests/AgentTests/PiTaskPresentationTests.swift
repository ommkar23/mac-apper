// @frontmatter:start
// Verifies service Pi task updates reach client-owned presentation state.
// @frontmatter:end
import Foundation
import Testing
@testable import AgentApplication
@testable import AgentMacosClient
import AgentMacosClientModel

@MainActor @Test func piRPCParserPublishesEveryTaskPlanUpdate() throws {
	var parser = PiRPCParser()
	let initial = Data(
		(#"{"type":"tool_execution_end","toolCallId":"plan-1","toolName":"plan","isError":false,"result":{"details":{"response":{"result":{"metadata":{"plan":{"tasks":[{"id":"design","title":"Design the app","status":"in_progress"},{"id":"build","title":"Build the app","status":"pending"}]}}}}}}}"#
			+ "\n").utf8)
	let progress = Data(
		(#"{"type":"tool_execution_end","toolCallId":"plan-2","toolName":"plan","isError":false,"result":{"details":{"response":{"result":{"metadata":{"plan":{"tasks":[{"id":"design","title":"Design the app","status":"completed"},{"id":"build","title":"Build the app","status":"in_progress"}]}}}}}}}"#
			+ "\n").utf8)
	let state = AppModel()

	for event in try parser.feed(initial) {
		if case .tasksUpdated(let tasks) = event {
			state.accept(
				.tasksUpdated(
					try tasks.map {
						try AgentMacosClientModel.AgentTaskRecord(
							id: $0.id, title: $0.title, status: $0.status.rawValue)
					}))
		}
	}
	#expect(state.tasks.map(\.status) == ["in_progress", "pending"])

	for event in try parser.feed(progress) {
		if case .tasksUpdated(let tasks) = event {
			state.accept(
				.tasksUpdated(
					try tasks.map {
						try AgentMacosClientModel.AgentTaskRecord(
							id: $0.id, title: $0.title, status: $0.status.rawValue)
					}))
		}
	}
	#expect(state.tasks.map(\.status) == ["completed", "in_progress"])
}
