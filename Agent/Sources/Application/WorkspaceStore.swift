// @frontmatter:start
// Owns local project and session preparation, history loading, and scoped preview paths.
// @frontmatter:end
import Foundation

@MainActor public final class LocalWorkspaceStore: WorkspaceStore {
	private let projectsRoot: URL
	private let sessionDirectory: (URL) -> URL
	public init(
		projectsRoot: URL,
		sessionDirectory: @escaping (URL) -> URL = ChatSessionCatalog.defaultDirectory
	) {
		self.projectsRoot = projectsRoot
		self.sessionDirectory = sessionDirectory
	}

	public func loadLibrary() async throws -> [WorkspaceGroup] {
		try WorkspaceLibrary.discover(in: projectsRoot)
	}

	public func loadProject(_ project: URL, session: URL?) async throws -> WorkspaceOpenResult {
		try validateProject(project)
		let directory = sessionDirectory(project)
		let sessions = try ChatSessionCatalog.discover(in: project, sessionDirectory: directory)
		let history = try (session ?? sessions.first?.file).map {
			try ChatSessionCatalog.load($0, in: project, sessionDirectory: directory)
		}
		return WorkspaceOpenResult(
			project: project, sessions: sessions, history: history,
			isChatOnly: project.lastPathComponent == ".chat")
	}

	public func loadSessions(in project: URL) async throws -> [ChatSessionSummary] {
		try validateProject(project)
		return try ChatSessionCatalog.discover(in: project, sessionDirectory: sessionDirectory(project))
	}

	public func loadChatProject() async throws -> WorkspaceOpenResult? {
		let chat = WorkspaceLibrary.chatProject(in: projectsRoot)
		var directory: ObjCBool = false
		guard
			FileManager.default.fileExists(atPath: chat.path, isDirectory: &directory),
			directory.boolValue
		else { return nil }
		return try await loadProject(chat, session: nil)
	}

	public func prepareChatSession(request: String) async throws -> WorkspacePreparedSession {
		try createProjectsRoot()
		let project = WorkspaceLibrary.chatProject(in: projectsRoot)
		try FileManager.default.createDirectory(
			at: project, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
		try validateProject(project)
		return try createSession(in: project, request: request, creatingApp: false)
	}

	public func prepareCreateProject(request: String) async throws -> WorkspacePreparedSession {
		try createProjectsRoot()
		let project = try ProjectScaffold.create(under: projectsRoot)
		return try createSession(in: project, request: request, creatingApp: true)
	}

	public func prepareCreateSession(in project: URL, request: String) async throws
		-> WorkspacePreparedSession
	{
		try validateProject(project)
		guard
			UUID(uuidString: project.lastPathComponent) != nil
		else { throw WorkspaceError.invalidPath }
		return try createSession(in: project, request: request, creatingApp: false)
	}

	public func resumeSession(in project: URL, sessionFile: URL) async throws
		-> WorkspacePreparedSession
	{
		try validateProject(project)
		guard
			project.lastPathComponent == ".chat"
				|| UUID(uuidString: project.lastPathComponent) != nil
		else { throw WorkspaceError.invalidPath }
		_ = try ChatSessionCatalog.load(
			sessionFile, in: project, sessionDirectory: sessionDirectory(project))
		return WorkspacePreparedSession(
			project: project, sessionFile: sessionFile,
			title: "", isNew: false, creatingApp: false)
	}

	private func createProjectsRoot() throws {
		try FileManager.default.createDirectory(
			at: projectsRoot, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
	}

	private func createSession(in project: URL, request: String, creatingApp: Bool) throws
		-> WorkspacePreparedSession
	{
		let directory = sessionDirectory(project)
		try FileManager.default.createDirectory(
			at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
		let file = directory.appendingPathComponent("\(UUID().uuidString.lowercased()).jsonl")
		try ChatSessionCatalog.validate(file, in: project, sessionDirectory: directory)
		return WorkspacePreparedSession(
			project: project, sessionFile: file,
			title: ChatSessionCatalog.title(for: request), isNew: true, creatingApp: creatingApp)
	}

	public func validatePreview(relativePath: String, project: URL) async throws -> URL? {
		try validateProject(project)
		guard
			relativePath.hasPrefix("dist/"),
			!relativePath.contains("..")
		else { return nil }
		let candidate = project.appendingPathComponent(relativePath).standardizedFileURL
		guard
			candidate.path.hasPrefix(project.standardizedFileURL.path + "/"),
			FileManager.default.isReadableFile(atPath: candidate.path)
		else { return nil }
		return candidate
	}

	public func diagnosticDirectory(for project: URL) async throws -> URL {
		try validateProject(project)
		return sessionDirectory(project)
	}

	private func validateProject(_ project: URL) throws {
		let root = projectsRoot.resolvingSymlinksInPath().standardizedFileURL
		guard
			project.isFileURL,
			project.resolvingSymlinksInPath().deletingLastPathComponent().standardizedFileURL.path
				== root.path,
			try FileManager.default.attributesOfItem(atPath: project.path)[.type] as? FileAttributeType
				== .typeDirectory
		else { throw WorkspaceError.invalidPath }
	}
}
