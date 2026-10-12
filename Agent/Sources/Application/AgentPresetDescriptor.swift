// @frontmatter:start
// Defines the legacy XPC descriptor for the fixed Chat and Create agents.
// @frontmatter:end
import Foundation

public enum AgentRuntimeMode: String, Codable, Sendable, Equatable {
	case conversation
	case project
}

public struct AgentPresetDescriptor: Codable, Sendable, Equatable, Identifiable {
	public let id: String
	public let displayName: String
	public let runtimeMode: AgentRuntimeMode

	public init(id: String, displayName: String, runtimeMode: AgentRuntimeMode) {
		self.id = id
		self.displayName = displayName
		self.runtimeMode = runtimeMode
	}
}
