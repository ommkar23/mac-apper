// @frontmatter:start
// Creates Agent operation and subscription controllers sharing service-owned managers.
// @frontmatter:end
import Foundation

struct ControllerFactory: Sendable {
	let sessions: any AgentSessionManaging
	let workspace: any AgentWorkspaceManaging

	func controllers() -> OpenXPCGeneratedService.Controllers {
		.init(
			listPresets: ListPresetsController(),
			startSession: StartSessionController(sessions: sessions),
			promptSession: PromptSessionController(sessions: sessions),
			sessionHistory: SessionHistoryController(sessions: sessions),
			abortSession: AbortSessionController(sessions: sessions),
			stopSession: StopSessionController(sessions: sessions),
			workspace: WorkspaceController(workspace: workspace),
			prepareChatSession: PrepareChatSessionController(workspace: workspace),
			prepareCreateProject: PrepareCreateProjectController(workspace: workspace),
			prepareCreateSession: PrepareCreateSessionController(workspace: workspace),
			resumeSession: ResumeSessionController(workspace: workspace),
			sessionEvents: SessionEventsController(sessions: sessions))
	}
}
