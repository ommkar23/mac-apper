// @frontmatter:start
// Tests server-side workspace preparation and catalog responses.
// @frontmatter:end
import Foundation
import Testing
@testable import AgentApplication

@Test func workspaceRequestHasNoFlagBasedPreparationFields() throws {
	let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
		.deletingLastPathComponent().deletingLastPathComponent()
	let spec = try String(contentsOf: root.appendingPathComponent("OpenXPC.yaml"), encoding: .utf8)
	let request = try #require(
		spec.components(separatedBy: "  - name: WorkspaceRequest\n").dropFirst().first?
			.components(separatedBy: "  - name: WorkspaceMessageRecord\n").first)
	for field in ["currentProjectPath", "isChatOnly", "existingSessionPath", "name: request"] {
		#expect(!request.contains(field))
	}
	#expect(spec.contains("name: prepareChatSession, request: PrepareChatSessionRequest"))
	#expect(spec.contains("name: prepareCreateProject, request: PrepareCreateProjectRequest"))
	#expect(spec.contains("name: prepareCreateSession, request: PrepareCreateSessionRequest"))
}

@Test func workspaceContractHasSeparateChatCreateAndResumeOperations() throws {
	let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
		.deletingLastPathComponent().deletingLastPathComponent()
	let spec = try String(contentsOf: root.appendingPathComponent("OpenXPC.yaml"), encoding: .utf8)
	for name in [
		"prepareChatSession", "prepareCreateProject", "prepareCreateSession", "resumeSession",
	] {
		#expect(spec.contains("name: \(name)"))
	}
}

@MainActor @Test func serviceKeepsChatInOneProjectAndCreatesSessionsInExistingCreateProjects()
	async throws
{
	let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
	defer { try? FileManager.default.removeItem(at: root) }
	let manager = WorkspaceDataManager(projectsRoot: root, preparations: SessionPreparationRegistry())
	func prepared(_ request: WorkspaceServiceRequest) async throws -> WorkspacePreparedRecord {
		guard
			case .prepared(let value) = try await manager.handle(request)
		else { throw WorkspaceError.invalidPath }
		return value
	}
	let chat1 = try await prepared(.prepareChatSession(request: "One"))
	let chat2 = try await prepared(.prepareChatSession(request: "Two"))
	#expect(chat1.projectPath == chat2.projectPath)
	#expect(URL(fileURLWithPath: chat1.projectPath).lastPathComponent == ".chat")
	#expect(chat1.sessionFilePath != chat2.sessionFilePath)
	let first = try await prepared(.prepareCreateProject(request: "Build one"))
	let next = try await prepared(
		.prepareCreateSession(
			projectPath: first.projectPath, request: "New conversation"))
	#expect(first.projectPath == next.projectPath)
	#expect(first.sessionFilePath != next.sessionFilePath)
	#expect(!FileManager.default.fileExists(atPath: first.sessionFilePath))
	await #expect(throws: (any Error).self) {
		_ = try await manager.handle(
			.resumeSession(
				projectPath: first.projectPath, sessionFilePath: first.sessionFilePath))
	}
	#expect(!FileManager.default.fileExists(atPath: first.sessionFilePath))
	let header =
		try JSONSerialization.data(withJSONObject: [
			"type": "session", "version": 3, "cwd": first.projectPath,
		]) + Data([10])
	try header.write(to: URL(fileURLWithPath: first.sessionFilePath))
	let resumed = try await prepared(
		.resumeSession(
			projectPath: first.projectPath, sessionFilePath: first.sessionFilePath))
	#expect(resumed.projectPath == first.projectPath)
	#expect(resumed.sessionFilePath == first.sessionFilePath)
	#expect(!resumed.isNew && !resumed.creatingApp)
	#expect(try Data(contentsOf: URL(fileURLWithPath: first.sessionFilePath)) == header)
	await #expect(throws: (any Error).self) {
		_ = try await manager.handle(
			.prepareCreateSession(
				projectPath: chat1.projectPath, request: "Not a Create project"))
	}
}

@MainActor @Test func serviceWorkspaceManagerOwnsProjectCreationAndCatalogData() async throws {
	let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
	defer { try? FileManager.default.removeItem(at: root) }
	let manager = WorkspaceDataManager(projectsRoot: root, preparations: SessionPreparationRegistry())

	let response = try await manager.handle(.prepareCreateProject(request: "Build a timer"))
	guard
		case .prepared(let prepared) = response
	else {
		Issue.record("Expected prepared response")
		return
	}
	#expect(FileManager.default.fileExists(atPath: prepared.projectPath))
	#expect(prepared.creatingApp)

	let library = try await manager.handle(.library)
	guard
		case .library(let snapshot) = library
	else {
		Issue.record("Expected library response")
		return
	}
	#expect(snapshot.groups.contains { !$0.isChatOnly && $0.title == "Generated App" })
}
