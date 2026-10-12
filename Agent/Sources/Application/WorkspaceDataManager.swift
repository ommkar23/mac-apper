// @frontmatter:start
// Handles workspace XPC requests and converts stored projects and histories to wire snapshots.
// @frontmatter:end
import Foundation

@MainActor public final class WorkspaceDataManager: AgentWorkspaceManaging {
	private let store: LocalWorkspaceStore
	private let preparations: SessionPreparationRegistry

	public init(projectsRoot: URL, preparations: SessionPreparationRegistry) {
		store = LocalWorkspaceStore(projectsRoot: projectsRoot)
		self.preparations = preparations
	}

	public func handle(_ request: WorkspaceServiceRequest) async throws -> WorkspaceServiceResponse {
		switch request {
		case .library:
			return .library(try .init(groups: try await store.loadLibrary().map(Self.group)))
		case .open(let projectPath, let sessionPath):
			let value = try await store.loadProject(
				URL(fileURLWithPath: projectPath),
				session: sessionPath.map { URL(fileURLWithPath: $0) })
			return .open(try Self.open(value))
		case .chatProject:
			return .open(try await store.loadChatProject().map(Self.open))
		case .sessions(let projectPath):
			return .sessions(
				try await store.loadSessions(in: URL(fileURLWithPath: projectPath)).map(Self.session))
		case .prepareChatSession(let request):
			return try await prepared(request: request, agentID: "chat") {
				try await store.prepareChatSession(request: request)
			}
		case .prepareCreateProject(let request):
			return try await prepared(request: request, agentID: "create") {
				try await store.prepareCreateProject(request: request)
			}
		case .prepareCreateSession(let projectPath, let request):
			return try await prepared(request: request, agentID: "create") {
				try await store.prepareCreateSession(
					in: URL(fileURLWithPath: projectPath), request: request)
			}
		case .resumeSession(let projectPath, let sessionFilePath):
			let value = try await store.resumeSession(
				in: URL(fileURLWithPath: projectPath),
				sessionFile: URL(fileURLWithPath: sessionFilePath))
			let response = try Self.wire(value)
			try preparations.issue(
				value, agentID: value.project.lastPathComponent == ".chat" ? "chat" : "create")
			return response
		case .validatePreview(let relativePath, let projectPath):
			let value = try await store.validatePreview(
				relativePath: relativePath, project: URL(fileURLWithPath: projectPath))
			return .path(value?.path)
		case .diagnosticDirectory(let projectPath):
			return .path(try await store.diagnosticDirectory(for: URL(fileURLWithPath: projectPath)).path)
		}
	}

	private func prepared(
		request: String, agentID: String, operation: () async throws -> WorkspacePreparedSession
	) async throws -> WorkspaceServiceResponse {
		guard
			request.utf8.count <= 65_536
		else { throw WorkspaceError.invalidPath }
		let value = try await operation()
		let response = try Self.wire(value)
		try preparations.issue(value, agentID: agentID)
		return response
	}

	private static func wire(_ value: WorkspacePreparedSession) throws -> WorkspaceServiceResponse {
		.prepared(
			try .init(
				projectPath: value.project.path, sessionFilePath: value.sessionFile.path,
				title: value.title, isNew: value.isNew, creatingApp: value.creatingApp))
	}

	private static func session(_ value: ChatSessionSummary) throws -> WorkspaceSessionRecord {
		try .init(
			filePath: value.file.path, title: value.title,
			modified: value.modified.timeIntervalSinceReferenceDate)
	}

	private static func group(_ value: WorkspaceGroup) throws -> WorkspaceGroupRecord {
		try .init(
			projectPath: value.project.path, title: value.title, isChatOnly: value.isChatOnly,
			app: try value.app.map {
				try WorkspaceAppRecord(
					name: $0.name, projectName: $0.projectName, bundlePath: $0.bundleURL.path)
			},
			sessions: try value.sessions.map(session))
	}

	private static func open(_ value: WorkspaceOpenResult) throws -> WorkspaceOpenRecord {
		try .init(
			projectPath: value.project.path,
			sessions: try value.sessions.map(session),
			history: try value.history.map { history in
				try WorkspaceHistoryRecord(
					summary: session(history.summary),
					messages: try history.messages.map {
						try WorkspaceMessageRecord(isUser: $0.isUser, text: $0.text)
					})
			},
			isChatOnly: value.isChatOnly)
	}
}
