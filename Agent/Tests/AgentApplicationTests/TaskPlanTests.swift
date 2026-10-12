// @frontmatter:start
// Tests valid task plan decoding and rejection of malformed or conflicting tasks.
// @frontmatter:end
import Foundation
import Testing

@testable import AgentApplication

@Test func taskPlanDecodesTypedProgress() throws {
	let data = Data(
		#"{"tasks":[{"id":"model-tests","title":"Test model","status":"in_progress"}]}"#.utf8)
	let plan = try TaskPlan.decode(data)
	#expect(plan.tasks.count == 1)
	#expect(plan.tasks.first?.status == .inProgress)
}

@Test(arguments: [
	#"{"tasks":[],"command":"shell"}"#,
	#"{"tasks":[{"id":"a","title":"A","status":"pending","shell":"x"}]}"#,
	#"{"tasks":[{"id":"a","title":"A","status":"pending"},{"id":"a","title":"B","status":"pending"}]}"#,
	#"{"tasks":[{"id":"../a","title":"A","status":"pending"}]}"#,
	#"{"tasks":[{"id":"a","title":" ","status":"pending"}]}"#,
	#"{"tasks":[{"id":"a","title":"A","status":"in_progress"},{"id":"b","title":"B","status":"in_progress"}]}"#,
]) func taskPlanRejectsInvalidPayloads(json: String) {
	#expect(throws: (any Error).self) { try TaskPlan.decode(Data(json.utf8)) }
}
