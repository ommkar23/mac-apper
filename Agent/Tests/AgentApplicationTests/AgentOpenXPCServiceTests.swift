// @frontmatter:start
// Tests generated OpenXPC request dispatch and routing to service-owned managers.
// @frontmatter:end
@testable import AgentApplication
import Foundation
import Testing

@MainActor private final class SessionManagerFixture: AgentSessionManaging {
	var stoppedSessionIDs: [String] = []
	var stopError: AgentProcessManagerError?
	var historyEvents: [SequencedAgentServiceEvent] = []
	var historyFailure: String?
	var projectPath = "/test/.chat"
	var prompts: [AgentSessionPromptRequest] = []
	func projectPath(sessionID: String) throws -> String { projectPath }
	func start(_ request: AgentSessionStartRequest) async throws -> Int { 0 }
	func prompt(_ request: AgentSessionPromptRequest) async throws { prompts.append(request) }
	func history(sessionID: String, cursor: Int) throws -> AgentSessionEventBatch {
		guard
			!historyEvents.isEmpty
		else { return .init(events: [], nextCursor: cursor, terminal: false, failure: nil) }
		return .init(
			events: historyEvents.filter { $0.sequence >= cursor },
			nextCursor: historyEvents.last!.sequence + 1,
			terminal: true, failure: historyFailure)
	}
	func abort(sessionID: String) async throws {}
	func stop(sessionID: String) async throws -> Bool {
		if let stopError { throw stopError }
		stoppedSessionIDs.append(sessionID)
		return true
	}
}

@MainActor private final class RecordingWorkspaceManager: AgentWorkspaceManaging {
	var requests: [WorkspaceServiceRequest] = []
	func handle(_ request: WorkspaceServiceRequest) async throws -> WorkspaceServiceResponse {
		requests.append(request)
		switch request {
		case .library: return .library(try .init(groups: []))
		case .open, .chatProject: return .open(nil)
		case .sessions: return .sessions([])
		case .validatePreview, .diagnosticDirectory: return .path(nil)
		default:
			return .prepared(
				try .init(
					projectPath: "/test/.chat", sessionFilePath: "/test/.chat/id.jsonl",
					title: "Hello", isNew: true, creatingApp: false))
		}
	}
}

private struct GeneratedRequestFixture: Encodable {
	let version = 1
	let requestID = UUID()
	let projectID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
	let sessionID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
	let command: String
	let payload: Data
}

private struct GeneratedResponseFixture: Decodable {
	let success: Bool
	let payload: Data?
}

@MainActor @Test func generatedControllersRejectMismatchedEnvelopeIdentifiers() async throws {
	let sessions = SessionManagerFixture()
	let workspace = RecordingWorkspaceManager()
	let controllers = ControllerFactory(sessions: sessions, workspace: workspace).controllers()
	let zero = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
	let other = UUID()
	let id = UUID()
	let path = "/test/.chat"
	let file = "\(path)/.pi/sessions/\(id.uuidString).jsonl"
	let start = try StartSessionRequest(
		sessionID: id.uuidString, agentID: "chat", projectPath: path,
		sessionFilePath: file, title: nil, firstRequest: false)
	await #expect(throws: (any Error).self) {
		_ = try await controllers.startSession.handle(other, id, start)
	}
	await #expect(throws: (any Error).self) {
		_ = try await controllers.startSession.handle(zero, other, start)
	}
	await #expect(throws: (any Error).self) {
		_ = try await controllers.promptSession.handle(
			other, id, PromptSessionRequest(sessionID: id.uuidString, message: "Go"))
	}
	await #expect(throws: (any Error).self) {
		_ = try await controllers.promptSession.handle(
			zero, other, PromptSessionRequest(sessionID: id.uuidString, message: "Go"))
	}
	#expect(sessions.prompts.isEmpty)
	try await controllers.promptSession.handle(
		zero, id, PromptSessionRequest(sessionID: id.uuidString, message: "Go"))
	#expect(sessions.prompts.count == 1)
	await #expect(throws: (any Error).self) {
		_ = try await controllers.sessionHistory.handle(
			other, id, SessionHistoryRequest(sessionID: id.uuidString, cursor: 0))
	}
	await #expect(throws: (any Error).self) {
		_ = try await controllers.abortSession.handle(
			other, id, SessionIdentifier(sessionID: id.uuidString))
	}
	await #expect(throws: (any Error).self) {
		_ = try await controllers.stopSession.handle(
			other, id, SessionIdentifier(sessionID: id.uuidString))
	}
	#expect(sessions.stoppedSessionIDs.isEmpty)
	await #expect(throws: (any Error).self) {
		_ = try await controllers.prepareCreateSession.handle(
			zero, zero,
			PrepareCreateSessionRequest(projectPath: "/test/\(other.uuidString)", request: "Build"))
	}
	await #expect(throws: (any Error).self) {
		_ = try await controllers.resumeSession.handle(
			other, id, ResumeSessionRequest(projectPath: path, sessionFilePath: file))
	}
	let open = try WorkspaceRequest(
		kind: "open", projectPath: path, sessionPath: file, relativePath: nil)
	await #expect(throws: (any Error).self) {
		_ = try await controllers.workspace.handle(zero, zero, open)
	}
	#expect(workspace.requests.isEmpty)
}

@MainActor @Test func generatedListenerDispatchesTypedWorkspaceOperation() async throws {
	let workspace = RecordingWorkspaceManager()
	let service = OpenXPCGeneratedService(
		controllers: ControllerFactory(
			sessions: SessionManagerFixture(), workspace: workspace
		).controllers())
	let request = try JSONEncoder().encode(
		GeneratedRequestFixture(
			command: "prepareChatSession",
			payload: JSONEncoder().encode(
				PrepareChatSessionRequest(request: "Hello"))))
	let data = await withCheckedContinuation { continuation in
		service.execute(request) { continuation.resume(returning: $0) }
	}
	let response = try JSONDecoder().decode(GeneratedResponseFixture.self, from: data)
	#expect(response.success)
	let prepared = try JSONDecoder().decode(
		SessionPreparationResponse.self, from: #require(response.payload))
	#expect(prepared.prepared.projectPath == "/test/.chat")
	#expect(workspace.requests == [.prepareChatSession(request: "Hello")])
}

@MainActor @Test func generatedListenerDispatchesPresetQuery() async throws {
	let service = OpenXPCGeneratedService(
		controllers: ControllerFactory(
			sessions: SessionManagerFixture(), workspace: RecordingWorkspaceManager()
		).controllers())
	let request = try JSONEncoder().encode(
		GeneratedRequestFixture(
			command: "listPresets", payload: JSONEncoder().encode(PresetListRequest())))
	let data = await withCheckedContinuation { continuation in
		service.execute(request) { continuation.resume(returning: $0) }
	}
	let response = try JSONDecoder().decode(GeneratedResponseFixture.self, from: data)
	#expect(response.success)
	let result = try JSONDecoder().decode(PresetListResponse.self, from: #require(response.payload))
	#expect(result.descriptors.map(\.id) == ["chat", "create"])
}

@MainActor @Test func generatedServiceRejectsLegacyWorkspacePreparation() async throws {
	let workspace = RecordingWorkspaceManager()
	let controllers = ControllerFactory(
		sessions: SessionManagerFixture(), workspace: workspace
	).controllers()
	let zero = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
	let legacy = try WorkspaceRequest(
		kind: "prepare", projectPath: nil, sessionPath: nil, relativePath: nil)
	await #expect(throws: (any Error).self) {
		_ = try await controllers.workspace.handle(zero, zero, legacy)
	}
	#expect(workspace.requests.isEmpty)
}

@MainActor @Test func generatedWorkspaceReadsRejectExtraOrMissingFields() async throws {
	let workspace = RecordingWorkspaceManager()
	let controllers = ControllerFactory(
		sessions: SessionManagerFixture(), workspace: workspace
	).controllers()
	let zero = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
	for (kind, project, session, relative) in [
		("library", "/foreign", nil, nil),
		("chatProject", nil, "/foreign", nil),
		("open", nil, nil, nil),
		("open", "/project", nil, "dist/image.png"),
		("sessions", "/project", "/session", nil),
		("validatePreview", "/project", nil, nil),
		("validatePreview", "/project", "/session", "dist/image.png"),
		("diagnosticDirectory", "/project", nil, "dist/image.png"),
	] {
		let request = try WorkspaceRequest(
			kind: kind, projectPath: project, sessionPath: session, relativePath: relative)
		await #expect(throws: (any Error).self) {
			_ = try await controllers.workspace.handle(zero, zero, request)
		}
	}
	#expect(workspace.requests.isEmpty)
	let projectID = UUID()
	let sessionID = UUID()
	let path = "/test/\(projectID.uuidString)"
	let file = "\(path)/.pi/sessions/\(sessionID.uuidString).jsonl"
	let valid = try WorkspaceRequest(
		kind: "open", projectPath: path, sessionPath: file, relativePath: nil)
	let result = try await controllers.workspace.handle(projectID, sessionID, valid)
	#expect(result.kind == "open")
	let library = try WorkspaceRequest(
		kind: "library", projectPath: nil, sessionPath: nil, relativePath: nil)
	#expect(try await controllers.workspace.handle(zero, zero, library).kind == "library")
	let preview = try WorkspaceRequest(
		kind: "validatePreview", projectPath: path, sessionPath: nil,
		relativePath: "dist/image.png")
	#expect(try await controllers.workspace.handle(projectID, zero, preview).kind == "path")
	#expect(
		workspace.requests == [
			.open(projectPath: path, sessionPath: file),
			.library, .validatePreview(relativePath: "dist/image.png", projectPath: path),
		])
}

@MainActor @Test func generatedHistoryPagesWithinPayloadLimitWithoutLosingEvents() async throws {
	let sessions = SessionManagerFixture()
	let workspace = RecordingWorkspaceManager()
	let start = 40
	sessions.historyEvents = (start..<(start + 128)).map {
		SequencedAgentServiceEvent(
			sequence: $0, event: .textDelta(String(repeating: "x", count: 900)))
	}
	sessions.historyFailure = "terminal failure"
	let controllers = ControllerFactory(sessions: sessions, workspace: workspace).controllers()
	let zero = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
	let sessionID = UUID()
	var cursor = start
	var pages = 0
	repeat {
		let response = try await controllers.sessionHistory.handle(
			zero, sessionID, SessionHistoryRequest(sessionID: sessionID.uuidString, cursor: cursor))
		let batch = response.batch
		let encodedSize = try JSONEncoder().encode(response).count
		#expect(encodedSize <= 65_536)
		#expect(!batch.events.isEmpty)
		#expect(batch.events.map(\.sequence) == Array(cursor..<batch.nextCursor))
		if batch.nextCursor < start + 128 {
			#expect(!batch.terminal)
			#expect(batch.failure == nil)
		} else {
			#expect(batch.terminal)
			#expect(batch.failure == "terminal failure")
		}
		cursor = batch.nextCursor
		pages += 1
	} while cursor < start + 128 && pages < 10
	#expect(cursor == start + 128)
	#expect(pages > 1)
}

@MainActor @Test func generatedHistoryRejectsAnEventThatCannotFitAlone() async throws {
	let sessions = SessionManagerFixture()
	let tasks = (0..<128).map {
		AgentServiceTask(id: "task-\($0)", title: String(repeating: "x", count: 700), status: "pending")
	}
	sessions.historyEvents = [.init(sequence: 0, event: .tasksUpdated(tasks))]
	let controllers = ControllerFactory(
		sessions: sessions, workspace: RecordingWorkspaceManager()
	).controllers()
	let zero = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
	let sessionID = UUID()
	await #expect(throws: (any Error).self) {
		_ = try await controllers.sessionHistory.handle(
			zero, sessionID, SessionHistoryRequest(sessionID: sessionID.uuidString, cursor: 0))
	}
}

@MainActor @Test func generatedServiceRoutesPreparationAndStopThroughApplicationManagers()
	async throws
{
	let sessions = SessionManagerFixture()
	let workspace = RecordingWorkspaceManager()
	let controllers = ControllerFactory(sessions: sessions, workspace: workspace).controllers()
	let zero = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
	let prepared = try await controllers.prepareChatSession.handle(
		zero, zero, PrepareChatSessionRequest(request: "Hello"))
	#expect(prepared.prepared.projectPath == "/test/.chat")
	#expect(workspace.requests == [.prepareChatSession(request: "Hello")])
	let sessionID = UUID()
	let stopped = try await controllers.stopSession.handle(
		zero, sessionID, SessionIdentifier(sessionID: sessionID.uuidString))
	#expect(stopped.success)
	#expect(sessions.stoppedSessionIDs == [sessionID.uuidString])
}
