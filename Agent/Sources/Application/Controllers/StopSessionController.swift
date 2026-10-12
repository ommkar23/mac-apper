// @frontmatter:start
// Validates a session binding and stops the service-owned Pi session.
// @frontmatter:end
import Foundation

struct StopSessionController: OpenXPCStopSessionController {
	let sessions: any AgentSessionManaging

	func handle(_ projectID: UUID, _ sessionID: UUID, _ request: SessionIdentifier) async throws
		-> Acknowledgement
	{
		try await AgentOpenXPCService.checkSession(
			projectID, sessionID, request.sessionID, sessions: sessions)
		return try await Acknowledgement(success: sessions.stop(sessionID: request.sessionID))
	}
}
