// @frontmatter:start
// Tests conversion of workspace XPC snapshots into client-owned model data.
// @frontmatter:end
import AgentMacosClientModel
import Foundation
import Testing
@testable import AgentMacosClient

private actor WorkspaceTransportFixture: AgentWorkspaceTransport {
	var responses: [WorkspaceServiceResponse]
	private(set) var requests: [WorkspaceServiceRequest] = []
	init(_ responses: [WorkspaceServiceResponse]) { self.responses = responses }
	func workspace(_ request: WorkspaceServiceRequest) async throws -> WorkspaceServiceResponse {
		requests.append(request)
		return responses.removeFirst()
	}
}

@MainActor @Test func workspaceStoreRequestsDistinctChatCreateAndResumeOperations() async throws {
	let prepared = WorkspaceServiceResponse.prepared(
		try .init(
			projectPath: "/service/project", sessionFilePath: "/service/project/.pi/sessions/id.jsonl",
			title: "Test", isNew: true, creatingApp: false))
	let transport = WorkspaceTransportFixture(Array(repeating: prepared, count: 4))
	let store = AgentXPCWorkspaceStore(transport: transport)
	let project = URL(fileURLWithPath: "/service/project")
	let session = URL(fileURLWithPath: "/service/project/.pi/sessions/id.jsonl")
	_ = try await store.prepareChatSession(request: "Chat")
	_ = try await store.prepareCreateProject(request: "Build")
	_ = try await store.prepareCreateSession(in: project, request: "More")
	_ = try await store.resumeSession(in: project, sessionFile: session)
	#expect(
		await transport.requests == [
			.prepareChatSession(request: "Chat"), .prepareCreateProject(request: "Build"),
			.prepareCreateSession(projectPath: project.path, request: "More"),
			.resumeSession(projectPath: project.path, sessionFilePath: session.path),
		])
}

@MainActor @Test func xpcWorkspaceStoreMapsServiceSnapshotsIntoModelData() async throws {
	let modified = Date.distantPast
	let transport = WorkspaceTransportFixture([
		.library(
			try WorkspaceLibraryRecord(groups: [
				WorkspaceGroupRecord(
					projectPath: "/service/id", title: "Service App", isChatOnly: false,
					app: WorkspaceAppRecord(
						name: "Service App", projectName: "id", bundlePath: "/service/out.app"),
					sessions: [
						WorkspaceSessionRecord(
							filePath: "/service/chat.jsonl", title: "Chat",
							modified: modified.timeIntervalSinceReferenceDate)
					])
			]))
	])
	let store = AgentXPCWorkspaceStore(transport: transport)

	let groups = try await store.loadLibrary()

	#expect(groups.count == 1)
	#expect(groups[0].title == "Service App")
	#expect(groups[0].app?.bundleURL.path == "/service/out.app")
	#expect(groups[0].sessions[0].modified == modified)
	#expect(await transport.requests == [.library])
}
