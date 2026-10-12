// @frontmatter:start
// Names client workspace operations and carries generated OpenXPC snapshot records.
// @frontmatter:end
import Foundation

public enum WorkspaceServiceRequest: Codable, Sendable, Equatable {
	case library
	case open(projectPath: String, sessionPath: String?)
	case chatProject
	case sessions(projectPath: String)
	case prepareChatSession(request: String)
	case prepareCreateProject(request: String)
	case prepareCreateSession(projectPath: String, request: String)
	case resumeSession(projectPath: String, sessionFilePath: String)
	case validatePreview(relativePath: String, projectPath: String)
	case diagnosticDirectory(projectPath: String)
}

public enum WorkspaceServiceResponse: Codable, Sendable, Equatable {
	case library(WorkspaceLibraryRecord)
	case open(WorkspaceOpenRecord?)
	case sessions([WorkspaceSessionRecord])
	case prepared(WorkspacePreparedRecord)
	case path(String?)
}
