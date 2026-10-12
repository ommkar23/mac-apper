// @frontmatter:start
// Handles a scoped plan request against the project's in-memory task store.
// @frontmatter:end
import Foundation

struct PlanController: OpenXPCPlanController {
	private let projects: ProjectResolver
	private let gate: DevToolsOperationGate
	private let plans = PlanStore()

	init(projects: ProjectResolver, gate: DevToolsOperationGate) {
		self.projects = projects
		self.gate = gate
	}

	func handle(_ projectID: UUID, _ sessionID: UUID, _ request: PlanRequest) async throws
		-> PlanResult
	{
		_ = try await projects.lookup(
			projectRoot: request.projectRoot,
			projectID: projectID.uuidString.lowercased(), sessionID: sessionID.uuidString)
		return try await gate.run {
			try await plans.execute(request, projectID: projectID.uuidString.lowercased())
		}
	}
}
