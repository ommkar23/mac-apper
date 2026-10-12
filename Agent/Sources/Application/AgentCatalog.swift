// @frontmatter:start
// Defines Chat and Create configurations and their authored Pi extension bindings.
// @frontmatter:end

public struct AgentDefinition: Sendable, Equatable, Identifiable {
	public let id: String
	public let displayName: String
	public let appIDs: [String]
	public let baseTools: [String]
	public let systemPrompt: String
	public let runtimeMode: AgentRuntimeMode

	public init(
		id: String, displayName: String, appIDs: [String], baseTools: [String],
		systemPrompt: String, runtimeMode: AgentRuntimeMode
	) {
		self.id = id
		self.displayName = displayName
		self.appIDs = appIDs
		self.baseTools = baseTools
		self.systemPrompt = systemPrompt
		self.runtimeMode = runtimeMode
	}
}

public enum AgentCatalog {
	static let chatExtensions: [(name: String, tools: [String], firstRequestOnly: Bool)] = [
		(name: "parallel-codemode.ts", tools: ["codemode"], firstRequestOnly: false)
	]

	static let createExtensions: [(name: String, tools: [String], firstRequestOnly: Bool)] = [
		(name: "parallel-codemode.ts", tools: ["codemode"], firstRequestOnly: false),
		(name: "create-instructions.ts", tools: [], firstRequestOnly: false),
		(name: "name-and-rename.ts", tools: ["set_app_name"], firstRequestOnly: false),
		(name: "create-app.ts", tools: [], firstRequestOnly: true),
	]

	public static let definitions: [AgentDefinition] = [
		AgentDefinition(
			id: "chat", displayName: "Chat", appIDs: [], baseTools: [],
			systemPrompt: """
				You are a helpful conversational assistant in Mac Apper.
				Use the supplied codemode capability for web search and fetch.
				""", runtimeMode: .conversation),
		AgentDefinition(
			id: "create", displayName: "Create", appIDs: ["dev-tools"],
			baseTools: ["read", "edit", "write", "grep", "find", "ls"],
			systemPrompt: """
				You are building a native macOS application for Mac Apper.
				Work only inside the current project and use Swift, SwiftUI, and Foundation.
				""", runtimeMode: .project),
	]

	public static var descriptors: [AgentPresetDescriptor] {
		definitions.map { .init(id: $0.id, displayName: $0.displayName, runtimeMode: $0.runtimeMode) }
	}
}
