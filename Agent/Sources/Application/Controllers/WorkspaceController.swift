// @frontmatter:start
// Validates and executes scoped workspace reads using the service-owned workspace manager.
// @frontmatter:end
import Foundation

struct WorkspaceController: OpenXPCWorkspaceController {
	let workspace: any AgentWorkspaceManaging

	func handle(_ projectID: UUID, _ sessionID: UUID, _ value: WorkspaceRequest) async throws
		-> WorkspaceResponse
	{
		let request = try AgentOpenXPCService.request(value)
		try AgentOpenXPCService.checkWorkspace(projectID, sessionID, request)
		return try AgentOpenXPCService.response(await workspace.handle(request))
	}
}
