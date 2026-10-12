// @frontmatter:start
// Prepares a Create project through the service-owned workspace manager.
// @frontmatter:end
import Foundation

struct PrepareCreateProjectController: OpenXPCPrepareCreateProjectController {
	let workspace: any AgentWorkspaceManaging

	func handle(_ projectID: UUID, _ sessionID: UUID, _ request: PrepareCreateProjectRequest)
		async throws -> SessionPreparationResponse
	{
		try AgentOpenXPCService.check(projectID, sessionID)
		return try AgentOpenXPCService.prepared(
			await workspace.handle(.prepareCreateProject(request: request.request)))
	}
}
