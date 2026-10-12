// @frontmatter:start
// Tests codable workspace preparation requests and library response snapshots.
// @frontmatter:end
import AgentApplication
import Foundation
import Testing

@Test func workspaceRequestsAndSnapshotsRoundTripAcrossXPC() throws {
	for request: WorkspaceServiceRequest in [
		.prepareChatSession(request: "Talk"),
		.prepareCreateProject(request: "Build it"),
		.prepareCreateSession(projectPath: "/tmp/projects/id", request: "Another session"),
		.resumeSession(projectPath: "/tmp/projects/id", sessionFilePath: "/tmp/projects/id/old.jsonl"),
	] {
		let requestData = try JSONEncoder().encode(request)
		#expect(try JSONDecoder().decode(WorkspaceServiceRequest.self, from: requestData) == request)
	}

	let modified = Date(timeIntervalSince1970: 10)
	let snapshot = try WorkspaceLibraryRecord(groups: [
		WorkspaceGroupRecord(
			projectPath: "/tmp/projects/id", title: "App", isChatOnly: false,
			app: WorkspaceAppRecord(name: "App", projectName: "id", bundlePath: "/tmp/output/App.app"),
			sessions: [
				WorkspaceSessionRecord(
					filePath: "/tmp/session.jsonl", title: "Build",
					modified: modified.timeIntervalSinceReferenceDate)
			])
	])
	#expect(snapshot.groups[0].sessions[0].modified == modified.timeIntervalSinceReferenceDate)
	#expect(throws: (any Error).self) {
		_ = try WorkspaceLibraryRecord(groups: Array(repeating: snapshot.groups[0], count: 129))
	}
	let response = WorkspaceServiceResponse.library(snapshot)
	let responseData = try JSONEncoder().encode(response)
	#expect(try JSONDecoder().decode(WorkspaceServiceResponse.self, from: responseData) == response)
}
