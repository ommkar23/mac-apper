// @frontmatter:start
// Tests the generated Agent client seam, scoped XPC adapter, and strict record adaptation.
// @frontmatter:end
@testable import AgentMacosClient
@testable import AgentMacosClientModel
import Foundation
import Testing

private final class ClientCreationCount: @unchecked Sendable {
	private let lock = NSLock()
	private var count = 0
	func record() { lock.withLock { count += 1 } }
	var value: Int { lock.withLock { count } }
}

private actor GeneratedCallProbe {
	let failure: (any Error)?
	init(failure: (any Error)? = nil) { self.failure = failure }
	private(set) var calls: [(String, UUID, UUID)] = []
	private(set) var startAgentID: String?
	private(set) var resumeFilePath: String?
	private(set) var workspaceKind: String?
	func startSession(_ request: StartSessionRequest, projectID: UUID, sessionID: UUID) async throws
		-> SessionAttachment
	{
		calls.append(("start", projectID, sessionID))
		startAgentID = request.agentID
		return try SessionAttachment(cursor: 9)
	}
	func promptSession(_ request: PromptSessionRequest, projectID: UUID, sessionID: UUID) async throws
		-> Acknowledgement
	{
		calls.append(("prompt", projectID, sessionID))
		return try Acknowledgement(success: true)
	}
	func sessionHistory(_ request: SessionHistoryRequest, projectID: UUID, sessionID: UUID)
		async throws -> SessionHistoryResponse
	{
		calls.append(("history", projectID, sessionID))
		return try SessionHistoryResponse(
			batch: SessionEventBatch(
				events: [], nextCursor: request.cursor, terminal: true, failure: nil))
	}
	func abortSession(_ request: SessionIdentifier, projectID: UUID, sessionID: UUID) async throws
		-> Acknowledgement
	{
		calls.append(("abort", projectID, sessionID))
		return try Acknowledgement(success: true)
	}
	func stopSession(_ request: SessionIdentifier, projectID: UUID, sessionID: UUID) async throws
		-> Acknowledgement
	{
		calls.append(("stop", projectID, sessionID))
		if let failure { throw failure }
		return try Acknowledgement(success: true)
	}
	func workspace(_ request: WorkspaceRequest, projectID: UUID, sessionID: UUID) async throws
		-> WorkspaceResponse
	{
		calls.append(("workspace", projectID, sessionID))
		workspaceKind = request.kind
		return try WorkspaceResponse(
			kind: "library", library: WorkspaceLibraryRecord(groups: []),
			openedProject: nil, sessions: nil, prepared: nil, path: nil)
	}
	private func prepared() throws -> SessionPreparationResponse {
		try SessionPreparationResponse(
			prepared: WorkspacePreparedRecord(
				projectPath: "/service/.chat", sessionFilePath: "/service/.chat/id.jsonl",
				title: "Title", isNew: true, creatingApp: false))
	}
	func prepareChatSession(_ request: PrepareChatSessionRequest, projectID: UUID, sessionID: UUID)
		async throws -> SessionPreparationResponse
	{
		calls.append(("chat", projectID, sessionID))
		return try prepared()
	}
	func prepareCreateProject(
		_ request: PrepareCreateProjectRequest, projectID: UUID, sessionID: UUID
	) async throws -> SessionPreparationResponse {
		calls.append(("createProject", projectID, sessionID))
		return try prepared()
	}
	func prepareCreateSession(
		_ request: PrepareCreateSessionRequest, projectID: UUID, sessionID: UUID
	) async throws -> SessionPreparationResponse {
		calls.append(("createSession", projectID, sessionID))
		return try prepared()
	}
	func resumeSession(_ request: ResumeSessionRequest, projectID: UUID, sessionID: UUID) async throws
		-> SessionPreparationResponse
	{
		calls.append(("resume", projectID, sessionID))
		resumeFilePath = request.sessionFilePath
		return try prepared()
	}
	func subscribe(_ request: SessionSubscriptionRequest, projectID: UUID, sessionID: UUID)
		async throws
		-> (SessionAttachment, AsyncThrowingStream<SessionEvent, any Error>)
	{
		calls.append(("subscribe", projectID, sessionID))
		return (try SessionAttachment(cursor: 0), AsyncThrowingStream { $0.finish() })
	}
}

private struct ProbeClient: AgentGeneratedClient {
	let probe: GeneratedCallProbe
	let projectID: UUID
	let sessionID: UUID
	func startSession(_ request: StartSessionRequest) async throws -> SessionAttachment {
		try await probe.startSession(request, projectID: projectID, sessionID: sessionID)
	}
	func promptSession(_ request: PromptSessionRequest) async throws -> Acknowledgement {
		try await probe.promptSession(request, projectID: projectID, sessionID: sessionID)
	}
	func sessionHistory(_ request: SessionHistoryRequest) async throws -> SessionHistoryResponse {
		try await probe.sessionHistory(request, projectID: projectID, sessionID: sessionID)
	}
	func abortSession(_ request: SessionIdentifier) async throws -> Acknowledgement {
		try await probe.abortSession(request, projectID: projectID, sessionID: sessionID)
	}
	func stopSession(_ request: SessionIdentifier) async throws -> Acknowledgement {
		try await probe.stopSession(request, projectID: projectID, sessionID: sessionID)
	}
	func workspace(_ request: WorkspaceRequest) async throws -> WorkspaceResponse {
		try await probe.workspace(request, projectID: projectID, sessionID: sessionID)
	}
	func prepareChatSession(_ request: PrepareChatSessionRequest) async throws
		-> SessionPreparationResponse
	{
		try await probe.prepareChatSession(request, projectID: projectID, sessionID: sessionID)
	}
	func prepareCreateProject(_ request: PrepareCreateProjectRequest) async throws
		-> SessionPreparationResponse
	{
		try await probe.prepareCreateProject(request, projectID: projectID, sessionID: sessionID)
	}
	func prepareCreateSession(_ request: PrepareCreateSessionRequest) async throws
		-> SessionPreparationResponse
	{
		try await probe.prepareCreateSession(request, projectID: projectID, sessionID: sessionID)
	}
	func resumeSession(_ request: ResumeSessionRequest) async throws -> SessionPreparationResponse {
		try await probe.resumeSession(request, projectID: projectID, sessionID: sessionID)
	}
	func subscribeSessionEvents(_ request: SessionSubscriptionRequest) async throws
		-> (SessionAttachment, AsyncThrowingStream<SessionEvent, any Error>)
	{
		try await probe.subscribe(request, projectID: projectID, sessionID: sessionID)
	}
}

private func adapter(_ probe: GeneratedCallProbe) -> AgentServiceXPCAdapter {
	AgentServiceXPCAdapter(makeClient: { projectID, sessionID in
		ProbeClient(probe: probe, projectID: projectID, sessionID: sessionID)
	})
}

@Test func generatedClientConformsToTheAdapterSeam() {
	let client: any AgentGeneratedClient = OpenXPCGeneratedClient(
		projectID: UUID(), sessionID: UUID())
	#expect(client is OpenXPCGeneratedClient)
}

@Test func generatedTransportCallsTypedSessionOperationsAndPreservesIdentity() async throws {
	let probe = GeneratedCallProbe()
	let transport = adapter(probe)
	let project = UUID()
	let session = UUID()
	let value = try await transport.startSession(
		.init(
			sessionID: session.uuidString, agentID: "create",
			projectPath: "/service/\(project.uuidString)",
			sessionFilePath: "/service/\(project.uuidString)/.pi/sessions/\(session.uuidString).jsonl",
			title: nil, firstRequest: false))
	#expect(value == 9)
	try await transport.prompt(
		.init(sessionID: session.uuidString, message: "Go"),
		projectPath: "/service/\(project.uuidString)")
	let history = try await transport.history(
		.init(sessionID: session.uuidString, cursor: 2), projectPath: "/service/\(project.uuidString)")
	#expect(history.nextCursor == 2)
	try await transport.abort(
		sessionID: session.uuidString, projectPath: "/service/\(project.uuidString)")
	#expect(
		try await transport.stop(
			sessionID: session.uuidString, projectPath: "/service/\(project.uuidString)"))
	let calls = await probe.calls
	#expect(calls.map(\.0) == ["start", "prompt", "history", "abort", "stop"])
	#expect(calls.allSatisfy { $0.1 == project && $0.2 == session })
	#expect(await probe.startAgentID == "create")
}

@Test func generatedTransportSubscribesUsingTheSessionProject() async throws {
	let probe = GeneratedCallProbe()
	let transport = adapter(probe)
	let project = UUID()
	let session = UUID()
	let (cursor, _) = try await transport.subscribe(
		sessionID: session.uuidString, projectPath: "/service/\(project.uuidString)")
	#expect(cursor == 0)
	let calls = await probe.calls
	#expect(calls.count == 1 && calls[0].0 == "subscribe")
	#expect(calls[0].1 == project && calls[0].2 == session)
}

@Test func generatedTransportCallsDistinctWorkspaceOperations() async throws {
	let probe = GeneratedCallProbe()
	let transport = adapter(probe)
	let project = UUID()
	let session = UUID()
	let path = "/service/\(project.uuidString)"
	let file = "\(path)/.pi/sessions/\(session.uuidString).jsonl"
	_ = try await transport.workspace(.prepareChatSession(request: "Talk"))
	_ = try await transport.workspace(.prepareCreateProject(request: "Build"))
	_ = try await transport.workspace(.prepareCreateSession(projectPath: path, request: "Again"))
	_ = try await transport.workspace(.resumeSession(projectPath: path, sessionFilePath: file))
	_ = try await transport.workspace(.sessions(projectPath: path))
	_ = try await transport.workspace(.open(projectPath: path, sessionPath: file))
	_ = try await transport.workspace(.library)
	let calls = await probe.calls
	#expect(
		calls.map(\.0) == [
			"chat", "createProject", "createSession", "resume", "workspace", "workspace", "workspace",
		])
	#expect(
		calls[4].1 == project && calls[4].2 == UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
	)
	#expect(calls[5].1 == project && calls[5].2 == session)
	#expect(
		calls[2].1 == project && calls[2].2 == UUID(uuidString: "00000000-0000-0000-0000-000000000000"))
	#expect(calls[3].1 == project && calls[3].2 == session)
	#expect(await probe.resumeFilePath == file)
	#expect(await probe.workspaceKind == "library")
}

@Test func generatedTransportRejectsNonUUIDSessionIdentifiers() async {
	let probe = GeneratedCallProbe()
	let transport = adapter(probe)
	await #expect(throws: AgentServiceTransportError.invalidRequest) {
		_ = try await transport.stop(sessionID: "not-a-uuid", projectPath: "/service/.chat")
	}
	#expect(await probe.calls.isEmpty)
}

@Test func generatedEventAdapterRejectsConflictingAndIncompleteVariants() throws {
	func record(kind: String, command: String? = nil, success: Bool? = nil, text: String? = nil)
		throws -> AgentEventRecord
	{
		try AgentEventRecord(
			kind: kind, id: nil, command: command, success: success,
			error: nil, text: text, name: nil, isError: nil, tasks: nil)
	}
	#expect(throws: AgentServiceTransportError.invalidResponse) {
		_ = try AgentServiceXPCAdapter.domainEvent(record(kind: "settled", text: "unexpected"))
	}
	#expect(throws: AgentServiceTransportError.invalidResponse) {
		_ = try AgentServiceXPCAdapter.domainEvent(record(kind: "tasksUpdated"))
	}
	#expect(throws: AgentServiceTransportError.invalidResponse) {
		_ = try AgentServiceXPCAdapter.domainEvent(record(kind: "response", command: "prompt"))
	}
	#expect(
		try AgentServiceXPCAdapter.domainEvent(record(kind: "textDelta", text: "hello"))
			== .textDelta("hello"))
}

@Test func generatedWorkspaceAdapterPreservesSessionDatesAndOptionalOpen() throws {
	let session = try WorkspaceSessionRecord(
		filePath: "/tmp/session.jsonl", title: "Chat", modified: 812_345_678)
	let response = try WorkspaceResponse(
		kind: "sessions", library: nil, openedProject: nil,
		sessions: [session], prepared: nil, path: nil)
	guard
		case .sessions(let sessions) = try AgentServiceXPCAdapter.domainWorkspace(response)
	else {
		Issue.record("unexpected workspace variant")
		return
	}
	#expect(sessions.count == 1)
	#expect(sessions[0].modified == 812_345_678)
	let missing = try WorkspaceResponse(
		kind: "open", library: nil, openedProject: nil,
		sessions: nil, prepared: nil, path: nil)
	guard
		case .open(nil) = try AgentServiceXPCAdapter.domainWorkspace(missing)
	else {
		Issue.record("optional open was lost")
		return
	}
}

@Test func generatedWorkspaceAdapterRejectsConflictingVariants() throws {
	let response = try WorkspaceResponse(
		kind: "path", library: WorkspaceLibraryRecord(groups: []),
		openedProject: nil, sessions: nil, prepared: nil, path: "/tmp/logs")
	#expect(throws: AgentServiceTransportError.invalidResponse) {
		_ = try AgentServiceXPCAdapter.domainWorkspace(response)
	}
}

@Test func generatedAgentRecordsBoundTextAndNestedCollections() throws {
	let task = try AgentTaskRecord(id: "design", title: "Design", status: "pending")
	#expect(throws: (any Error).self) {
		_ = try AgentTaskRecord(
			id: String(repeating: "x", count: 257), title: "Design", status: "pending")
	}
	#expect(throws: (any Error).self) {
		_ = try AgentEventRecord(
			kind: "tasksUpdated", id: nil, command: nil, success: nil,
			error: nil, text: nil, name: nil, isError: nil, tasks: Array(repeating: task, count: 129))
	}
	let settled = try AgentEventRecord(
		kind: "settled", id: nil, command: nil,
		success: nil, error: nil, text: nil, name: nil, isError: nil, tasks: nil)
	let event = try SessionEvent(sequence: 17, event: settled)
	#expect(
		try SessionEventBatch(events: [event], nextCursor: 18, terminal: true, failure: nil).events == [
			event
		])
}

@Test func adapterCreatesAClientForEveryServiceRequest() async throws {
	let probe = GeneratedCallProbe()
	let creations = ClientCreationCount()
	let client = AgentServiceXPCAdapter(makeClient: { projectID, sessionID in
		creations.record()
		return ProbeClient(probe: probe, projectID: projectID, sessionID: sessionID)
	})
	_ = try await client.stop(sessionID: UUID().uuidString, projectPath: "/service/.chat")
	_ = try await client.stop(sessionID: UUID().uuidString, projectPath: "/service/.chat")
	#expect(creations.value == 2)
	#expect(await probe.calls.count == 2)
}

@Test func adapterPreservesGeneratedClientFailures() async {
	let client = adapter(GeneratedCallProbe(failure: OpenXPCGeneratedFailure.remoteFailure))
	await #expect(throws: OpenXPCGeneratedFailure.self) {
		_ = try await client.stop(sessionID: UUID().uuidString, projectPath: "/service/.chat")
	}
}
