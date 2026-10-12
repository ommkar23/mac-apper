// @frontmatter:start
// Validates scoped session starts and attaches to service-owned Pi sessions.
// @frontmatter:end
import Foundation

struct StartSessionController: OpenXPCStartSessionController {
	let sessions: any AgentSessionManaging

	func handle(_ projectID: UUID, _ sessionID: UUID, _ request: StartSessionRequest) async throws
		-> SessionAttachment
	{
		try AgentOpenXPCService.check(
			projectID, sessionID, projectPath: request.projectPath,
			sessionPath: request.sessionFilePath)
		guard
			UUID(uuidString: request.sessionID) == sessionID
		else { throw OpenXPCGeneratedFailure.invalidRequest }
		return try await SessionAttachment(cursor: sessions.start(request))
	}
}
