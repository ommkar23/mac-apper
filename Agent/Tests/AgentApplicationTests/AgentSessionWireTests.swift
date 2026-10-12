// @frontmatter:start
// Tests session start requests and each service event kind across Codable boundaries.
// @frontmatter:end
import AgentApplication
import Foundation
import Testing

@Test func sessionStartRequestRoundTripsAcrossXPC() throws {
	let request = try AgentSessionStartRequest(
		sessionID: "session-1",
		agentID: "create",
		projectPath: "/tmp/projects/project-1",
		sessionFilePath: "/tmp/projects/project-1/.pi/sessions/session-1.jsonl",
		title: "Build notes",
		firstRequest: true
	)
	let generated: StartSessionRequest = request
	let data = try JSONEncoder().encode(generated)
	#expect(try JSONDecoder().decode(AgentSessionStartRequest.self, from: data) == request)
}

@Test func everyAgentEventKindRoundTripsAcrossXPC() throws {
	let events: [AgentServiceEvent] = [
		.response(id: "1", command: "prompt", success: true, error: nil),
		.textDelta("Hello"),
		.tasksUpdated([.init(id: "a", title: "Build", status: "in_progress")]),
		.toolStarted(id: "tool", name: "build", text: "{}"),
		.toolUpdated(id: "tool", name: "build", text: "Compiling"),
		.toolFinished(id: "tool", name: "build", text: "Done", isError: false),
		.notification("Renamed"),
		.extensionError("Failed"),
		.settled,
	]
	for event in events {
		let data = try JSONEncoder().encode(event)
		#expect(try JSONDecoder().decode(AgentServiceEvent.self, from: data) == event)
	}
}
