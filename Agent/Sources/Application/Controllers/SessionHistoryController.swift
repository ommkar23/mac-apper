// @frontmatter:start
// Pages a scoped session's durable events within the XPC payload bound.
// @frontmatter:end
import Foundation

struct SessionHistoryController: OpenXPCSessionHistoryController {
	let sessions: any AgentSessionManaging

	func handle(_ projectID: UUID, _ sessionID: UUID, _ request: SessionHistoryRequest) async throws
		-> SessionHistoryResponse
	{
		try await AgentOpenXPCService.checkSession(
			projectID, sessionID, request.sessionID, sessions: sessions)
		let page = try await sessions.history(sessionID: request.sessionID, cursor: request.cursor)
		return try AgentOpenXPCService.historyResponse(page, cursor: request.cursor)
	}
}
