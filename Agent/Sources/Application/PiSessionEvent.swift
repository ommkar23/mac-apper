// @frontmatter:start
// Defines domain session events and errors adapted at the Agent XPC boundary.
// @frontmatter:end
import Foundation

public enum PiRPCError: Error, Equatable, Sendable {
	case invalidRecord
	case recordTooLarge
	case incompleteRecord
	case rejected(String)
	case unavailable
}

public enum PiRPCEvent: Equatable, Sendable {
	case response(id: String?, command: String, success: Bool, error: String?)
	case textDelta(String)
	case tasksUpdated([PlanTask])
	case toolStarted(id: String, name: String, argumentsJSON: String)
	case toolUpdated(id: String, name: String, text: String)
	case toolFinished(id: String, name: String, text: String, isError: Bool)
	case notification(String)
	case extensionError(String)
	case settled
}
