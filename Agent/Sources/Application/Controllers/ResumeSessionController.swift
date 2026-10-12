// @frontmatter:start
// Validates a project and session path before resuming a service-owned session binding.
// @frontmatter:end
import Foundation

struct ResumeSessionController: OpenXPCResumeSessionController {
	let workspace: any AgentWorkspaceManaging

	func handle(_ projectID: UUID, _ sessionID: UUID, _ request: ResumeSessionRequest) async throws
		-> SessionPreparationResponse
	{
		try AgentOpenXPCService.check(
			projectID, sessionID, projectPath: request.projectPath,
			sessionPath: request.sessionFilePath)
		return try AgentOpenXPCService.prepared(
			await workspace.handle(
				.resumeSession(
					projectPath: request.projectPath, sessionFilePath: request.sessionFilePath)))
	}
}
