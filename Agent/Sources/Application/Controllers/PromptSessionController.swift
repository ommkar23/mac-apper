// @frontmatter:start
// Checks the session binding before forwarding a prompt to the service-owned Pi session.
// @frontmatter:end
import Foundation

struct PromptSessionController: OpenXPCPromptSessionController {
	let sessions: any AgentSessionManaging

	func handle(_ projectID: UUID, _ sessionID: UUID, _ request: PromptSessionRequest) async throws
		-> Acknowledgement
	{
		try await AgentOpenXPCService.checkSession(
			projectID, sessionID, request.sessionID, sessions: sessions)
		try await sessions.prompt(request)
		return try Acknowledgement(success: true)
	}
}
