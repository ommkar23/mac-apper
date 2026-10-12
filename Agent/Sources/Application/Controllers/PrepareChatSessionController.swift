// @frontmatter:start
// Prepares a Chat session through the service-owned workspace manager.
// @frontmatter:end
import Foundation

struct PrepareChatSessionController: OpenXPCPrepareChatSessionController {
	let workspace: any AgentWorkspaceManaging

	func handle(_ projectID: UUID, _ sessionID: UUID, _ request: PrepareChatSessionRequest)
		async throws -> SessionPreparationResponse
	{
		try AgentOpenXPCService.check(projectID, sessionID)
		return try AgentOpenXPCService.prepared(
			await workspace.handle(.prepareChatSession(request: request.request)))
	}
}
