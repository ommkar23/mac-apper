// @frontmatter:start
// Defines service-owned session and workspace interfaces for Agent OpenXPC controllers.
// @frontmatter:end
import Foundation

@MainActor public protocol AgentSessionManaging: AnyObject, Sendable {
	func projectPath(sessionID: String) throws -> String
	func start(_ request: AgentSessionStartRequest) async throws -> Int
	func prompt(_ request: AgentSessionPromptRequest) async throws
	func history(sessionID: String, cursor: Int) throws -> AgentSessionEventBatch
	func subscribe(
		sessionID: String, observer: @escaping (SequencedAgentServiceEvent) -> Void,
		onFinished: @escaping (String?) -> Void
	) throws -> (UUID, Int)
	func unsubscribe(sessionID: String, id: UUID)
	func abort(sessionID: String) async throws
	func stop(sessionID: String) async throws -> Bool
}

public extension AgentSessionManaging {
	func subscribe(
		sessionID: String, observer: @escaping (SequencedAgentServiceEvent) -> Void,
		onFinished: @escaping (String?) -> Void
	) throws -> (UUID, Int) {
		throw AgentProcessManagerError.unknownSession
	}
	func unsubscribe(sessionID: String, id: UUID) {}
}

@MainActor public protocol AgentWorkspaceManaging: AnyObject, Sendable {
	func handle(_ request: WorkspaceServiceRequest) async throws -> WorkspaceServiceResponse
}
