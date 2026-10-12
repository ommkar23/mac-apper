// @frontmatter:start
// Keeps client domain events and history batches alongside generated OpenXPC requests.
// @frontmatter:end
import Foundation

public typealias AgentSessionStartRequest = StartSessionRequest
public typealias AgentSessionPromptRequest = PromptSessionRequest
public typealias AgentSessionPollRequest = SessionHistoryRequest

public enum AgentServiceEvent: Codable, Sendable, Equatable {
	case response(id: String?, command: String, success: Bool, error: String?)
	case textDelta(String)
	case tasksUpdated([AgentTaskRecord])
	case toolStarted(id: String, name: String, text: String)
	case toolUpdated(id: String, name: String, text: String)
	case toolFinished(id: String, name: String, text: String, isError: Bool)
	case notification(String)
	case extensionError(String)
	case settled
}

public struct SequencedAgentServiceEvent: Codable, Sendable, Equatable {
	public let sequence: Int
	public let event: AgentServiceEvent
	public init(sequence: Int, event: AgentServiceEvent) {
		self.sequence = sequence
		self.event = event
	}
}

public struct AgentSessionEventBatch: Codable, Sendable, Equatable {
	public let events: [SequencedAgentServiceEvent]
	public let nextCursor: Int
	public let terminal: Bool
	public let failure: String?

	public init(
		events: [SequencedAgentServiceEvent], nextCursor: Int, terminal: Bool, failure: String?
	) {
		self.events = events
		self.nextCursor = nextCursor
		self.terminal = terminal
		self.failure = failure
	}
}
