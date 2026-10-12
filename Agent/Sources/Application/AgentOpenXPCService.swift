// @frontmatter:start
// Validates Agent envelope IDs and adapts workspace, history, and event records at the XPC boundary.
// @frontmatter:end
import Foundation

enum AgentOpenXPCService {

	private static let zeroID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
	private static let historyPayloadLimit = 65_536  // Agent/OpenXPC.yaml maxPayloadBytes

	static func check(
		_ projectID: UUID, _ sessionID: UUID, projectPath: String? = nil,
		sessionPath: String? = nil
	) throws {
		let expectedProject: UUID
		if let projectPath {
			let name = URL(fileURLWithPath: projectPath).lastPathComponent
			if name == ".chat" {
				expectedProject = zeroID
			} else if let id = UUID(uuidString: name) {
				expectedProject = id
			} else {
				throw OpenXPCGeneratedFailure.invalidRequest
			}
		} else {
			expectedProject = zeroID
		}
		let expectedSession: UUID
		if let sessionPath {
			guard
				let id = UUID(
					uuidString: URL(fileURLWithPath: sessionPath)
						.deletingPathExtension().lastPathComponent)
			else { throw OpenXPCGeneratedFailure.invalidRequest }
			expectedSession = id
		} else {
			expectedSession = zeroID
		}
		guard
			projectID == expectedProject,
			sessionID == expectedSession
		else { throw OpenXPCGeneratedFailure.invalidRequest }
	}

	@MainActor static func checkSession(
		_ projectID: UUID, _ sessionID: UUID, _ identifier: String,
		sessions: any AgentSessionManaging
	) throws {
		guard
			UUID(uuidString: identifier) == sessionID
		else { throw OpenXPCGeneratedFailure.invalidRequest }
		let projectPath = try sessions.projectPath(sessionID: identifier)
		try check(projectID, zeroID, projectPath: projectPath)
	}

	static func checkWorkspace(
		_ projectID: UUID, _ sessionID: UUID, _ request: WorkspaceServiceRequest
	) throws {
		switch request {
		case .library, .chatProject: try check(projectID, sessionID)
		case .open(let path, let session):
			try check(projectID, sessionID, projectPath: path, sessionPath: session)
		case .sessions(let path), .diagnosticDirectory(let path):
			try check(projectID, sessionID, projectPath: path)
		case .validatePreview(_, let path):
			try check(projectID, sessionID, projectPath: path)
		case .prepareChatSession, .prepareCreateProject, .prepareCreateSession, .resumeSession:
			throw OpenXPCGeneratedFailure.invalidRequest
		}
	}

	static func historyResponse(_ page: AgentSessionEventBatch, cursor: Int) throws
		-> SessionHistoryResponse
	{
		let (end, overflow) = cursor.addingReportingOverflow(page.events.count)
		guard
			cursor >= 0,
			!overflow,
			page.nextCursor == end,
			page.events.enumerated().allSatisfy({ $0.element.sequence == cursor + $0.offset })
		else { throw OpenXPCGeneratedFailure.invalidResponse }
		var events = try page.events.map(event)
		while true {
			let complete = events.count == page.events.count
			let result = try SessionHistoryResponse(
				batch: SessionEventBatch(
					events: events, nextCursor: cursor + events.count,
					terminal: complete && page.terminal, failure: complete ? page.failure : nil))
			if try JSONEncoder().encode(result).count <= historyPayloadLimit { return result }
			// A nonempty journal page must always advance the cursor.
			guard
				events.count > 1
			else { throw OpenXPCGeneratedFailure.invalidResponse }
			events.removeLast()
		}
	}

	private static func recode<Source: Encodable, Result: Decodable>(_ value: Source) throws -> Result
	{
		try JSONDecoder().decode(Result.self, from: JSONEncoder().encode(value))
	}

	static func event(_ item: SequencedAgentServiceEvent) throws -> SessionEvent {
		try SessionEvent(sequence: item.sequence, event: record(item.event))
	}

	private static func record(_ event: AgentServiceEvent) throws -> AgentEventRecord {
		var kind: String
		var id: String?
		var command: String?
		var success: Bool?
		var error: String?
		var text: String?
		var name: String?
		var isError: Bool?
		var tasks: [AgentTaskRecord]?
		switch event {
		case .response(let valueID, let valueCommand, let valueSuccess, let valueError):
			kind = "response"; id = valueID; command = valueCommand
			success = valueSuccess; error = valueError
		case .textDelta(let value): kind = "textDelta"; text = value
		case .tasksUpdated(let values):
			kind = "tasksUpdated"; tasks = try values.map { try recode($0) }
		case .toolStarted(let valueID, let valueName, let valueText):
			kind = "toolStarted"; id = valueID; name = valueName; text = valueText
		case .toolUpdated(let valueID, let valueName, let valueText):
			kind = "toolUpdated"; id = valueID; name = valueName; text = valueText
		case .toolFinished(let valueID, let valueName, let valueText, let valueError):
			kind = "toolFinished"; id = valueID; name = valueName
			text = valueText; isError = valueError
		case .notification(let value): kind = "notification"; text = value
		case .extensionError(let value): kind = "extensionError"; text = value
		case .settled: kind = "settled"
		}
		return try AgentEventRecord(
			kind: kind, id: id, command: command, success: success, error: error,
			text: text, name: name, isError: isError, tasks: tasks)
	}

	static func request(_ value: WorkspaceRequest) throws -> WorkspaceServiceRequest {
		switch value.kind {
		case "library":
			guard
				value.projectPath == nil,
				value.sessionPath == nil,
				value.relativePath == nil
			else { throw OpenXPCGeneratedFailure.invalidRequest }
			return .library
		case "chatProject":
			guard
				value.projectPath == nil,
				value.sessionPath == nil,
				value.relativePath == nil
			else { throw OpenXPCGeneratedFailure.invalidRequest }
			return .chatProject
		case "open":
			guard
				let path = value.projectPath,
				value.relativePath == nil
			else { throw OpenXPCGeneratedFailure.invalidRequest }
			return .open(projectPath: path, sessionPath: value.sessionPath)
		case "sessions":
			guard
				let path = value.projectPath,
				value.sessionPath == nil,
				value.relativePath == nil
			else { throw OpenXPCGeneratedFailure.invalidRequest }
			return .sessions(projectPath: path)
		case "validatePreview":
			guard
				let relative = value.relativePath,
				let path = value.projectPath,
				value.sessionPath == nil
			else { throw OpenXPCGeneratedFailure.invalidRequest }
			return .validatePreview(relativePath: relative, projectPath: path)
		case "diagnosticDirectory":
			guard
				let path = value.projectPath,
				value.sessionPath == nil,
				value.relativePath == nil
			else { throw OpenXPCGeneratedFailure.invalidRequest }
			return .diagnosticDirectory(projectPath: path)
		default: throw OpenXPCGeneratedFailure.invalidRequest
		}
	}

	static func prepared(_ response: WorkspaceServiceResponse) throws
		-> SessionPreparationResponse
	{
		guard
			case .prepared(let value) = response
		else { throw OpenXPCGeneratedFailure.invalidResponse }
		return try SessionPreparationResponse(prepared: value)
	}

	static func response(_ value: WorkspaceServiceResponse) throws -> WorkspaceResponse {
		var kind: String
		var library: WorkspaceLibraryRecord?
		var openedProject: WorkspaceOpenRecord?
		var sessions: [WorkspaceSessionRecord]?
		var prepared: WorkspacePreparedRecord?
		var path: String?
		switch value {
		case .library(let result): kind = "library"; library = result
		case .open(let result): kind = "open"; openedProject = result
		case .sessions(let result): kind = "sessions"; sessions = result
		case .prepared(let result): kind = "prepared"; prepared = result
		case .path(let result): kind = "path"; path = result
		}
		return try WorkspaceResponse(
			kind: kind, library: library, openedProject: openedProject,
			sessions: sessions, prepared: prepared, path: path)
	}
}
