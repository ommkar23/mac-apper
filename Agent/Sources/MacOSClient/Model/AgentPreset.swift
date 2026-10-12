// @frontmatter:start
// Defines the two fixed agent choices displayed by the client.
// @frontmatter:end
public struct AgentPresetSummary: Identifiable, Sendable, Equatable {
	public let id: String
	public let displayName: String

	public init(id: String, displayName: String) {
		self.id = id
		self.displayName = displayName
	}
}

public enum BuiltInAgentPresets {
	public static let all = [
		AgentPresetSummary(id: "chat", displayName: "Chat"),
		AgentPresetSummary(id: "create", displayName: "Create"),
	]
}
