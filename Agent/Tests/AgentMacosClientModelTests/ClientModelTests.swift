// @frontmatter:start
// Tests client-owned agent choices, app names, and task-plan decoding without application code.
// @frontmatter:end
import Foundation
import Testing
@testable import AgentMacosClientModel

@Test func clientAgentSelectionDoesNotModelADynamicRuntimeMode() throws {
	let source = try String(
		contentsOf: URL(fileURLWithPath: #filePath)
			.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
			.appendingPathComponent("Sources/MacOSClient/Model/AgentPreset.swift"), encoding: .utf8)
	#expect(!source.contains("AgentPresetRuntimeMode"))
}

@Test func clientModelOffersOnlyChatAndCreate() {
	#expect(BuiltInAgentPresets.all.map(\.id) == ["chat", "create"])
}

@Test func clientModelUsesGeneratedAgentTaskRecords() throws {
	let source = try String(
		contentsOf: URL(fileURLWithPath: #filePath)
			.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
			.appendingPathComponent("Sources/MacOSClient/Model/PiSessionEvent.swift"), encoding: .utf8)
	#expect(source.contains("case tasksUpdated([AgentTaskRecord])"))
	let task = try AgentTaskRecord(id: "design", title: "Design", status: "in_progress")
	#expect(task.status == "in_progress")
}

@Test func clientModelSanitizesRenameCommands() throws {
	let name = try AppName.sanitize("  Paper/Reader.app  ")
	#expect(name == "Paper Reader")
	#expect(try AppName.renameCommand(for: name).hasPrefix("/mac-apper-rename "))
	#expect(throws: AppNameError.self) { try AppName.sanitize("..") }
}
