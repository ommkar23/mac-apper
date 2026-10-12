// @frontmatter:start
// Validates and aborts a service-owned Pi session without changing its ownership.
// @frontmatter:end
import Foundation

struct AbortSessionController: OpenXPCAbortSessionController {
	let sessions: any AgentSessionManaging

	func handle(_ projectID: UUID, _ sessionID: UUID, _ request: SessionIdentifier) async throws
		-> Acknowledgement
	{
		try await AgentOpenXPCService.checkSession(
			projectID, sessionID, request.sessionID, sessions: sessions)
		try await sessions.abort(sessionID: request.sessionID)
		return try Acknowledgement(success: true)
	}
}
