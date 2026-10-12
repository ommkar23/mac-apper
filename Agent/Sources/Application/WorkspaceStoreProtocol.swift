// @frontmatter:start
// Defines the service-owned interface for local workspace storage operations.
// @frontmatter:end
import Foundation

@MainActor public protocol WorkspaceStore {
	func loadLibrary() async throws -> [WorkspaceGroup]
	func loadProject(_ project: URL, session: URL?) async throws -> WorkspaceOpenResult
	func loadSessions(in project: URL) async throws -> [ChatSessionSummary]
	func loadChatProject() async throws -> WorkspaceOpenResult?
	func prepareChatSession(request: String) async throws -> WorkspacePreparedSession
	func prepareCreateProject(request: String) async throws -> WorkspacePreparedSession
	func prepareCreateSession(in project: URL, request: String) async throws
		-> WorkspacePreparedSession
	func resumeSession(in project: URL, sessionFile: URL) async throws -> WorkspacePreparedSession
	func validatePreview(relativePath: String, project: URL) async throws -> URL?
	func diagnosticDirectory(for project: URL) async throws -> URL
}
