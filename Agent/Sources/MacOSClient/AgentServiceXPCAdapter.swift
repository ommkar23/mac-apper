// @frontmatter:start
// Maps client session and workspace operations to generated typed Agent XPC calls.
// @frontmatter:end
import AgentMacosClientModel
import Foundation

public protocol AgentGeneratedClient: Sendable {
	func startSession(_ request: StartSessionRequest) async throws -> SessionAttachment
	func promptSession(_ request: PromptSessionRequest) async throws -> Acknowledgement
	func sessionHistory(_ request: SessionHistoryRequest) async throws -> SessionHistoryResponse
	func abortSession(_ request: SessionIdentifier) async throws -> Acknowledgement
	func stopSession(_ request: SessionIdentifier) async throws -> Acknowledgement
	func workspace(_ request: WorkspaceRequest) async throws -> WorkspaceResponse
	func prepareChatSession(_ request: PrepareChatSessionRequest) async throws
		-> SessionPreparationResponse
	func prepareCreateProject(_ request: PrepareCreateProjectRequest) async throws
		-> SessionPreparationResponse
	func prepareCreateSession(_ request: PrepareCreateSessionRequest) async throws
		-> SessionPreparationResponse
	func resumeSession(_ request: ResumeSessionRequest) async throws -> SessionPreparationResponse
	func subscribeSessionEvents(_ request: SessionSubscriptionRequest) async throws
		-> (SessionAttachment, AsyncThrowingStream<SessionEvent, any Error>)
}

extension OpenXPCGeneratedClient: AgentGeneratedClient {}

public struct AgentServiceXPCAdapter: AgentSessionTransport, AgentWorkspaceTransport {
	private let makeClient: @Sendable (UUID, UUID) -> any AgentGeneratedClient

	public init(serviceName: String? = nil) {
		let serviceName = serviceName ?? Self.bundledServiceName() ?? "com.macapper.AgentXPCService"
		makeClient = { projectID, sessionID in
			OpenXPCGeneratedClient(
				projectID: projectID, sessionID: sessionID, serviceName: serviceName)
		}
	}

	private static func bundledServiceName() -> String? {
		let plist = Bundle.main.bundleURL.appendingPathComponent(
			"Contents/XPCServices/AgentXPCService.xpc/Contents/Info.plist")
		guard
			let values = try? plist.resourceValues(forKeys: [
				.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey,
			]),
			values.isRegularFile == true,
			values.isSymbolicLink != true,
			let size = values.fileSize,
			size <= 65_536,
			let data = try? Data(contentsOf: plist),
			let info = (try? PropertyListSerialization.propertyList(from: data, format: nil))
				as? [String: Any],
			let identifier = info["CFBundleIdentifier"] as? String,
			!identifier.isEmpty,
			identifier.utf8.count <= 256
		else { return nil }
		return identifier
	}

	public init(makeClient: @escaping @Sendable (UUID, UUID) -> any AgentGeneratedClient) {
		self.makeClient = makeClient
	}

	private func client(projectID: UUID, sessionID: UUID) -> any AgentGeneratedClient {
		makeClient(projectID, sessionID)
	}

	private static let emptyID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!

	private static func uuid(_ string: String) throws -> UUID {
		guard
			let id = UUID(uuidString: string)
		else { throw AgentServiceTransportError.invalidRequest }
		return id
	}

	private static func projectID(_ path: String) throws -> UUID {
		let name = URL(fileURLWithPath: path).lastPathComponent
		if name == ".chat" { return emptyID }
		return try uuid(name)
	}

	public func startSession(_ value: AgentSessionStartRequest) async throws -> Int {
		return try await client(
			projectID: Self.projectID(value.projectPath), sessionID: Self.uuid(value.sessionID)
		).startSession(value).cursor
	}

	public func prompt(_ value: AgentSessionPromptRequest, projectPath: String) async throws {
		let result = try await client(
			projectID: Self.projectID(projectPath), sessionID: Self.uuid(value.sessionID)
		).promptSession(value)
		guard
			result.success
		else { throw AgentServiceTransportError.invalidResponse }
	}

	public func history(_ value: AgentSessionPollRequest, projectPath: String) async throws
		-> AgentSessionEventBatch
	{
		let batch = try await client(
			projectID: Self.projectID(projectPath), sessionID: Self.uuid(value.sessionID)
		).sessionHistory(value).batch
		return AgentSessionEventBatch(
			events: try batch.events.map {
				.init(sequence: $0.sequence, event: try Self.domainEvent($0.event))
			},
			nextCursor: batch.nextCursor, terminal: batch.terminal, failure: batch.failure)
	}

	public func subscribe(sessionID: String, projectPath: String) async throws
		-> (Int, AsyncThrowingStream<SequencedAgentServiceEvent, any Error>)
	{
		let (ack, live) = try await client(
			projectID: Self.projectID(projectPath), sessionID: Self.uuid(sessionID)
		).subscribeSessionEvents(SessionSubscriptionRequest(sessionID: sessionID))
		let events = AsyncThrowingStream<SequencedAgentServiceEvent, any Error> { continuation in
			let task = Task {
				do {
					for try await record in live {
						continuation.yield(
							.init(
								sequence: record.sequence, event: try Self.domainEvent(record.event)))
					}
					continuation.finish()
				} catch { continuation.finish(throwing: error) }
			}
			continuation.onTermination = { @Sendable _ in task.cancel() }
		}
		return (ack.cursor, events)
	}

	public func abort(sessionID: String, projectPath: String) async throws {
		let result = try await client(
			projectID: Self.projectID(projectPath), sessionID: Self.uuid(sessionID)
		).abortSession(SessionIdentifier(sessionID: sessionID))
		guard
			result.success
		else { throw AgentServiceTransportError.invalidResponse }
	}

	public func stop(sessionID: String, projectPath: String) async throws -> Bool {
		try await client(
			projectID: Self.projectID(projectPath), sessionID: Self.uuid(sessionID)
		).stopSession(SessionIdentifier(sessionID: sessionID)).success
	}

	public func workspace(_ value: WorkspaceServiceRequest) async throws -> WorkspaceServiceResponse {
		switch value {
		case .prepareChatSession(let text):
			return .prepared(
				try await client(projectID: Self.emptyID, sessionID: Self.emptyID)
					.prepareChatSession(PrepareChatSessionRequest(request: text)).prepared)
		case .prepareCreateProject(let text):
			return .prepared(
				try await client(projectID: Self.emptyID, sessionID: Self.emptyID)
					.prepareCreateProject(PrepareCreateProjectRequest(request: text)).prepared)
		case .prepareCreateSession(let path, let text):
			return .prepared(
				try await client(projectID: Self.projectID(path), sessionID: Self.emptyID)
					.prepareCreateSession(
						PrepareCreateSessionRequest(projectPath: path, request: text)
					).prepared)
		case .resumeSession(let path, let file):
			return .prepared(
				try await client(
					projectID: Self.projectID(path),
					sessionID: Self.uuid(
						URL(fileURLWithPath: file).deletingPathExtension().lastPathComponent)
				).resumeSession(ResumeSessionRequest(projectPath: path, sessionFilePath: file)).prepared)
		default:
			let request = try Self.workspaceRequest(value)
			return try Self.domainWorkspace(
				await client(
					projectID: try request.projectPath.map(Self.projectID) ?? Self.emptyID,
					sessionID: try request.sessionPath.map {
						try Self.uuid(URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent)
					} ?? Self.emptyID
				).workspace(request))
		}
	}

	static func domainEvent(_ record: AgentEventRecord) throws -> AgentServiceEvent {
		func only(
			id: Bool = false, command: Bool = false, success: Bool = false,
			error: Bool = false, text: Bool = false, name: Bool = false,
			isError: Bool = false, tasks: Bool = false
		) throws {
			guard
				(id || record.id == nil),
				(command || record.command == nil),
				(success || record.success == nil),
				(error || record.error == nil),
				(text || record.text == nil),
				(name || record.name == nil),
				(isError || record.isError == nil),
				(tasks || record.tasks == nil)
			else { throw AgentServiceTransportError.invalidResponse }
		}
		switch record.kind {
		case "response":
			guard
				let command = record.command,
				let success = record.success
			else { throw AgentServiceTransportError.invalidResponse }
			try only(id: true, command: true, success: true, error: true)
			return .response(id: record.id, command: command, success: success, error: record.error)
		case "textDelta":
			guard
				let text = record.text
			else { throw AgentServiceTransportError.invalidResponse }
			try only(text: true)
			return .textDelta(text)
		case "tasksUpdated":
			guard
				let tasks = record.tasks
			else { throw AgentServiceTransportError.invalidResponse }
			try only(tasks: true)
			return .tasksUpdated(tasks)
		case "toolStarted", "toolUpdated", "toolFinished":
			guard
				let id = record.id,
				let name = record.name,
				let text = record.text
			else { throw AgentServiceTransportError.invalidResponse }
			switch record.kind {
			case "toolStarted":
				try only(id: true, text: true, name: true)
				return .toolStarted(id: id, name: name, text: text)
			case "toolUpdated":
				try only(id: true, text: true, name: true)
				return .toolUpdated(id: id, name: name, text: text)
			default:
				guard
					let isError = record.isError
				else { throw AgentServiceTransportError.invalidResponse }
				try only(id: true, text: true, name: true, isError: true)
				return .toolFinished(id: id, name: name, text: text, isError: isError)
			}
		case "notification":
			guard
				let text = record.text
			else { throw AgentServiceTransportError.invalidResponse }
			try only(text: true)
			return .notification(text)
		case "extensionError":
			guard
				let text = record.text
			else { throw AgentServiceTransportError.invalidResponse }
			try only(text: true)
			return .extensionError(text)
		case "settled":
			try only()
			return .settled
		default: throw AgentServiceTransportError.invalidResponse
		}
	}

	private static func workspaceRequest(_ value: WorkspaceServiceRequest) throws -> WorkspaceRequest
	{
		var kind: String
		var projectPath: String?
		var sessionPath: String?
		var relativePath: String?
		switch value {
		case .library: kind = "library"
		case .open(let project, let session):
			kind = "open"; projectPath = project; sessionPath = session
		case .chatProject: kind = "chatProject"
		case .sessions(let project): kind = "sessions"; projectPath = project
		case .prepareChatSession, .prepareCreateProject, .prepareCreateSession, .resumeSession:
			throw AgentServiceTransportError.invalidRequest
		case .validatePreview(let relative, let project):
			kind = "validatePreview"; relativePath = relative; projectPath = project
		case .diagnosticDirectory(let project):
			kind = "diagnosticDirectory"; projectPath = project
		}
		return try WorkspaceRequest(
			kind: kind, projectPath: projectPath, sessionPath: sessionPath,
			relativePath: relativePath)
	}

	static func domainWorkspace(_ value: WorkspaceResponse) throws -> WorkspaceServiceResponse {
		func only(
			library: Bool = false, openedProject: Bool = false,
			sessions: Bool = false, prepared: Bool = false, path: Bool = false
		) throws {
			guard
				(library || value.library == nil),
				(openedProject || value.openedProject == nil),
				(sessions || value.sessions == nil),
				(prepared || value.prepared == nil),
				(path || value.path == nil)
			else { throw AgentServiceTransportError.invalidResponse }
		}
		switch value.kind {
		case "library":
			guard
				let library = value.library
			else { throw AgentServiceTransportError.invalidResponse }
			try only(library: true)
			return .library(library)
		case "open":
			try only(openedProject: true)
			return .open(value.openedProject)
		case "sessions":
			guard
				let sessions = value.sessions
			else { throw AgentServiceTransportError.invalidResponse }
			try only(sessions: true)
			return .sessions(sessions)
		case "prepared":
			guard
				let prepared = value.prepared
			else { throw AgentServiceTransportError.invalidResponse }
			try only(prepared: true)
			return .prepared(prepared)
		case "path":
			try only(path: true)
			return .path(value.path)
		default: throw AgentServiceTransportError.invalidResponse
		}
	}
}
