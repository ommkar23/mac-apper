// @frontmatter:start
// Validates a Create project before preparing its service-owned session binding.
// @frontmatter:end
import Foundation

struct PrepareCreateSessionController: OpenXPCPrepareCreateSessionController {
	let workspace: any AgentWorkspaceManaging

	func handle(_ projectID: UUID, _ sessionID: UUID, _ request: PrepareCreateSessionRequest)
		async throws -> SessionPreparationResponse
	{
		try AgentOpenXPCService.check(projectID, sessionID, projectPath: request.projectPath)
		return try AgentOpenXPCService.prepared(
			await workspace.handle(
				.prepareCreateSession(
					projectPath: request.projectPath, request: request.request)))
	}
}
