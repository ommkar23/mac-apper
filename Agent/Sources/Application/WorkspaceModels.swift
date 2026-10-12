// @frontmatter:start
// Defines domain workspace values translated to and from Agent XPC snapshots.
// @frontmatter:end
import Foundation

public struct BuiltApp: Identifiable, Equatable, Sendable {
	public let name: String
	public let projectName: String
	public let bundleURL: URL

	public var id: URL { bundleURL }

	public init(name: String, projectName: String, bundleURL: URL) {
		self.name = name
		self.projectName = projectName
		self.bundleURL = bundleURL
	}
}

public struct ChatSessionSummary: Identifiable, Sendable {
	public var id: URL { file }
	public let file: URL
	public let title: String
	public let modified: Date

	public init(file: URL, title: String, modified: Date) {
		self.file = file
		self.title = title
		self.modified = modified
	}
}

public struct ChatSessionHistory: Sendable {
	public let summary: ChatSessionSummary
	public let messages: [ChatMessage]

	public init(summary: ChatSessionSummary, messages: [ChatMessage]) {
		self.summary = summary
		self.messages = messages
	}
}

public struct WorkspaceGroup: Identifiable, Sendable {
	public var id: URL { project }
	public let project: URL
	public let title: String
	public let isChatOnly: Bool
	public let app: BuiltApp?
	public let sessions: [ChatSessionSummary]

	public init(
		project: URL, title: String, isChatOnly: Bool, app: BuiltApp?, sessions: [ChatSessionSummary]
	) {
		self.project = project
		self.title = title
		self.isChatOnly = isChatOnly
		self.app = app
		self.sessions = sessions
	}
}

public struct WorkspaceOpenResult: Sendable {
	public let project: URL
	public let sessions: [ChatSessionSummary]
	public let history: ChatSessionHistory?
	public let isChatOnly: Bool

	public init(
		project: URL, sessions: [ChatSessionSummary], history: ChatSessionHistory?, isChatOnly: Bool
	) {
		self.project = project
		self.sessions = sessions
		self.history = history
		self.isChatOnly = isChatOnly
	}
}

public struct WorkspacePreparedSession: Sendable {
	public let project: URL
	public let sessionFile: URL
	public let title: String
	public let isNew: Bool
	public let creatingApp: Bool

	public init(project: URL, sessionFile: URL, title: String, isNew: Bool, creatingApp: Bool) {
		self.project = project
		self.sessionFile = sessionFile
		self.title = title
		self.isNew = isNew
		self.creatingApp = creatingApp
	}
}
