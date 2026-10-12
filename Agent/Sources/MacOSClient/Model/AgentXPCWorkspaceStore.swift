// @frontmatter:start
// Maps remote workspace requests and snapshots into client-owned workspace models.
// @frontmatter:end
import Foundation

public protocol AgentWorkspaceTransport: Sendable {
	func workspace(_ request: WorkspaceServiceRequest) async throws -> WorkspaceServiceResponse
}

public enum AgentXPCWorkspaceStoreError: Error {
	case invalidResponse
}

@MainActor public final class AgentXPCWorkspaceStore: WorkspaceStore {
	private let transport: any AgentWorkspaceTransport
	public init(transport: any AgentWorkspaceTransport) {
		self.transport = transport
	}

	public func loadLibrary() async throws -> [WorkspaceGroup] {
		guard
			case .library(let value) = try await transport.workspace(.library)
		else { throw AgentXPCWorkspaceStoreError.invalidResponse }
		return try value.groups.map(Self.group)
	}

	public func loadProject(_ project: URL, session: URL?) async throws -> WorkspaceOpenResult {
		guard
			case .open(let value?) = try await transport.workspace(
				.open(
					projectPath: project.path, sessionPath: session?.path))
		else { throw AgentXPCWorkspaceStoreError.invalidResponse }
		return try Self.open(value)
	}

	public func loadSessions(in project: URL) async throws -> [ChatSessionSummary] {
		guard
			case .sessions(let value) = try await transport.workspace(
				.sessions(projectPath: project.path))
		else { throw AgentXPCWorkspaceStoreError.invalidResponse }
		return try value.map(Self.session)
	}

	public func loadChatProject() async throws -> WorkspaceOpenResult? {
		guard
			case .open(let value) = try await transport.workspace(.chatProject)
		else { throw AgentXPCWorkspaceStoreError.invalidResponse }
		return try value.map(Self.open)
	}

	public func prepareChatSession(request: String) async throws -> WorkspacePreparedSession {
		try await prepared(.prepareChatSession(request: request))
	}

	public func prepareCreateProject(request: String) async throws -> WorkspacePreparedSession {
		try await prepared(.prepareCreateProject(request: request))
	}

	public func prepareCreateSession(in project: URL, request: String) async throws
		-> WorkspacePreparedSession
	{
		try await prepared(.prepareCreateSession(projectPath: project.path, request: request))
	}

	public func resumeSession(in project: URL, sessionFile: URL) async throws
		-> WorkspacePreparedSession
	{
		try await prepared(
			.resumeSession(
				projectPath: project.path, sessionFilePath: sessionFile.path))
	}

	private func prepared(_ operation: WorkspaceServiceRequest) async throws
		-> WorkspacePreparedSession
	{
		guard
			case .prepared(let value) = try await transport.workspace(operation)
		else { throw AgentXPCWorkspaceStoreError.invalidResponse }
		return WorkspacePreparedSession(
			project: try Self.url(value.projectPath),
			sessionFile: try Self.url(value.sessionFilePath),
			title: value.title, isNew: value.isNew, creatingApp: value.creatingApp)
	}

	public func validatePreview(relativePath: String, project: URL) async throws -> URL? {
		guard
			case .path(let path) = try await transport.workspace(
				.validatePreview(
					relativePath: relativePath, projectPath: project.path))
		else { throw AgentXPCWorkspaceStoreError.invalidResponse }
		return try path.map(Self.url)
	}

	public func diagnosticDirectory(for project: URL) async throws -> URL {
		guard
			case .path(let path?) = try await transport.workspace(
				.diagnosticDirectory(
					projectPath: project.path))
		else { throw AgentXPCWorkspaceStoreError.invalidResponse }
		return try Self.url(path)
	}

	private static func group(_ value: WorkspaceGroupRecord) throws -> WorkspaceGroup {
		WorkspaceGroup(
			project: try url(value.projectPath),
			title: value.title,
			isChatOnly: value.isChatOnly,
			app: try value.app.map { app in
				BuiltApp(name: app.name, projectName: app.projectName, bundleURL: try url(app.bundlePath))
			},
			sessions: try value.sessions.map(session))
	}

	private static func session(_ value: WorkspaceSessionRecord) throws -> ChatSessionSummary {
		ChatSessionSummary(
			file: try url(value.filePath), title: value.title,
			modified: Date(timeIntervalSinceReferenceDate: value.modified))
	}

	private static func open(_ value: WorkspaceOpenRecord) throws -> WorkspaceOpenResult {
		WorkspaceOpenResult(
			project: try url(value.projectPath),
			sessions: try value.sessions.map(session),
			history: try value.history.map { history in
				ChatSessionHistory(
					summary: try session(history.summary),
					messages: history.messages.map { ChatMessage(isUser: $0.isUser, text: $0.text) })
			},
			isChatOnly: value.isChatOnly)
	}

	private static func url(_ path: String) throws -> URL {
		guard
			path.hasPrefix("/"),
			path.utf8.count <= 4_096
		else { throw AgentXPCWorkspaceStoreError.invalidResponse }
		return URL(fileURLWithPath: path).standardizedFileURL
	}
}
