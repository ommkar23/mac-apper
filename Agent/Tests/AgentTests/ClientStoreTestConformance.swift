// @frontmatter:start
// Adapts the local service store to client-owned presentation values in integration tests.
// @frontmatter:end
import AgentApplication
import AgentMacosClientModel
import Foundation

@MainActor final class TestLocalWorkspaceStore: AgentMacosClientModel.WorkspaceStore {
	private let store: AgentApplication.LocalWorkspaceStore
	init(
		projectsRoot: URL,
		sessionDirectory: @escaping (URL) -> URL = AgentApplication.ChatSessionCatalog.defaultDirectory
	) {
		store = AgentApplication.LocalWorkspaceStore(
			projectsRoot: projectsRoot, sessionDirectory: sessionDirectory)
	}

	func loadLibrary() async throws -> [AgentMacosClientModel.WorkspaceGroup] {
		try await store.loadLibrary().map { group in
			.init(
				project: group.project, title: group.title, isChatOnly: group.isChatOnly,
				app: group.app.map {
					AgentMacosClientModel.BuiltApp(
						name: $0.name, projectName: $0.projectName, bundleURL: $0.bundleURL)
				}, sessions: group.sessions.map(Self.session))
		}
	}
	func loadProject(_ project: URL, session: URL?) async throws
		-> AgentMacosClientModel.WorkspaceOpenResult
	{
		Self.open(try await store.loadProject(project, session: session))
	}
	func loadSessions(in project: URL) async throws -> [AgentMacosClientModel.ChatSessionSummary] {
		try await store.loadSessions(in: project).map(Self.session)
	}
	func loadChatProject() async throws -> AgentMacosClientModel.WorkspaceOpenResult? {
		try await store.loadChatProject().map(Self.open)
	}
	func prepareChatSession(request: String) async throws
		-> AgentMacosClientModel.WorkspacePreparedSession
	{
		Self.prepared(try await store.prepareChatSession(request: request))
	}
	func prepareCreateProject(request: String) async throws
		-> AgentMacosClientModel.WorkspacePreparedSession
	{
		Self.prepared(try await store.prepareCreateProject(request: request))
	}
	func prepareCreateSession(in project: URL, request: String) async throws
		-> AgentMacosClientModel.WorkspacePreparedSession
	{
		Self.prepared(try await store.prepareCreateSession(in: project, request: request))
	}
	func resumeSession(in project: URL, sessionFile: URL) async throws
		-> AgentMacosClientModel.WorkspacePreparedSession
	{
		Self.prepared(try await store.resumeSession(in: project, sessionFile: sessionFile))
	}
	private static func prepared(_ value: AgentApplication.WorkspacePreparedSession)
		-> AgentMacosClientModel.WorkspacePreparedSession
	{
		// Match the production wire adapter: project path strings become directory URLs.
		.init(
			project: URL(fileURLWithPath: value.project.path, isDirectory: true),
			sessionFile: value.sessionFile, title: value.title,
			isNew: value.isNew, creatingApp: value.creatingApp)
	}
	func validatePreview(relativePath: String, project: URL) async throws -> URL? {
		try await store.validatePreview(relativePath: relativePath, project: project)
	}
	func diagnosticDirectory(for project: URL) async throws -> URL {
		try await store.diagnosticDirectory(for: project)
	}
	private static func session(_ value: AgentApplication.ChatSessionSummary)
		-> AgentMacosClientModel.ChatSessionSummary
	{
		.init(file: value.file, title: value.title, modified: value.modified)
	}
	private static func open(_ value: AgentApplication.WorkspaceOpenResult)
		-> AgentMacosClientModel.WorkspaceOpenResult
	{
		.init(
			project: value.project, sessions: value.sessions.map(session),
			history: value.history.map { history in
				AgentMacosClientModel.ChatSessionHistory(
					summary: session(history.summary),
					messages: history.messages.map {
						AgentMacosClientModel.ChatMessage(isUser: $0.isUser, text: $0.text)
					})
			}, isChatOnly: value.isChatOnly)
	}
}
