// @frontmatter:start
// Tests fixed Chat and Create selection and their session startup behavior.
// @frontmatter:end
import AgentMacosClientModel
import Foundation
import Testing
@testable import AgentMacosClient

@MainActor private final class AgentSelectionRuntime: AgentSessionRuntime {
	var startedAgentIDs: [String] = []
	var responseText: String?
	var stopCount = 0
	var continuation: AsyncThrowingStream<PiRPCEvent, any Error>.Continuation?
	func start(in project: URL) async throws -> AsyncThrowingStream<PiRPCEvent, any Error> {
		throw PiRPCError.unavailable
	}
	func start(in project: URL, sessionFile: URL, title: String?) async throws
		-> AsyncThrowingStream<PiRPCEvent, any Error>
	{
		throw PiRPCError.unavailable
	}
	func start(
		agentID: String, in project: URL, sessionFile: URL, title: String?, firstRequest: Bool
	) async throws -> AsyncThrowingStream<PiRPCEvent, any Error> {
		startedAgentIDs.append(agentID)
		if responseText != nil {
			let stream = AsyncThrowingStream<PiRPCEvent, any Error>.makeStream()
			continuation = stream.continuation
			return stream.stream
		}
		return AsyncThrowingStream {
			$0.yield(.settled)
			$0.finish()
		}
	}
	func prompt(_ message: String) async throws {
		if let responseText {
			continuation?.yield(.textDelta(responseText))
			continuation?.yield(.settled)
		}
	}
	func abort() async throws {}
	func detach() async -> Bool { true }
	func stop() async -> Bool { stopCount += 1; continuation?.finish(); return true }
}

@MainActor private final class AgentSelectionStore: AgentMacosClientModel.WorkspaceStore {
	let project: URL
	init(project: URL) { self.project = project }
	func loadLibrary() async throws -> [AgentMacosClientModel.WorkspaceGroup] { [] }
	func loadProject(_ project: URL, session: URL?) async throws
		-> AgentMacosClientModel.WorkspaceOpenResult
	{
		.init(project: project, sessions: [], history: nil, isChatOnly: true)
	}
	func loadSessions(in project: URL) async throws -> [AgentMacosClientModel.ChatSessionSummary] {
		[]
	}
	func loadChatProject() async throws -> AgentMacosClientModel.WorkspaceOpenResult? { nil }
	func prepareChatSession(request: String) async throws
		-> AgentMacosClientModel.WorkspacePreparedSession
	{
		.init(
			project: project, sessionFile: project.appendingPathComponent(".pi/sessions/chat.jsonl"),
			title: request, isNew: true, creatingApp: false)
	}
	func prepareCreateProject(request: String) async throws
		-> AgentMacosClientModel.WorkspacePreparedSession
	{ throw PiRPCError.unavailable }
	func prepareCreateSession(in project: URL, request: String) async throws
		-> AgentMacosClientModel.WorkspacePreparedSession
	{ throw PiRPCError.unavailable }
	func resumeSession(in project: URL, sessionFile: URL) async throws
		-> AgentMacosClientModel.WorkspacePreparedSession
	{ throw PiRPCError.unavailable }
	func validatePreview(relativePath: String, project: URL) async throws -> URL? { nil }
	func diagnosticDirectory(for project: URL) async throws -> URL { project }
}

@MainActor @Test func headlessChatUsesTheClientModelAndStopsItsSession() async {
	let runtime = AgentSelectionRuntime()
	runtime.responseText = "Hello"
	let result = await HeadlessChatCommand.run(
		message: "Say hello", runtime: runtime,
		store: AgentSelectionStore(project: URL(fileURLWithPath: "/fixture/.chat")))
	#expect(result.success)
	#expect(result.reply == "Hello")
	#expect(result.agentID == "chat")
	#expect(result.isChatOnly)
	#expect(result.status == "Completed")
	#expect(result.cleanupVerified)
	#expect(runtime.startedAgentIDs == ["chat"])
	// WorkspaceSession resets before starting, then the command stops its session.
	#expect(runtime.stopCount == 2)
}

@MainActor @Test func headlessChatRejectsEmptyMessagesWithoutPreparingAnything() async {
	let runtime = AgentSelectionRuntime()
	let result = await HeadlessChatCommand.run(
		message: "  ", runtime: runtime,
		store: AgentSelectionStore(project: URL(fileURLWithPath: "/fixture/.chat")))
	#expect(!result.success)
	#expect(result.sessionFilePath == nil)
	#expect(runtime.startedAgentIDs.isEmpty)
}

@MainActor @Test func workspaceOffersOnlyTheTwoBuiltInAgents() {
	let model = WorkspaceSession(runtime: AgentSelectionRuntime())
	#expect(model.agentPresets.map(\.id) == ["chat", "create"])
	#expect(model.selectedAgentID == "create")
	model.selectAgent("review")
	#expect(model.selectedAgentID == "create")
	model.selectAgent("chat")
	#expect(model.selectedAgentID == "chat")
	#expect(model.isChatOnly)
}

@MainActor @Test func fixedChatAndCreateDriveTheRuntime() async throws {
	let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
	defer { try? FileManager.default.removeItem(at: root) }
	let runtime = AgentSelectionRuntime()
	let model = WorkspaceSession(
		runtime: runtime,
		workspaceStore: AgentSelectionStore(project: root.appendingPathComponent(".chat")))
	model.selectAgent("chat")
	model.idea = "Discuss an idea"
	await model.submit()
	#expect(runtime.startedAgentIDs == ["chat"])
	#expect(model.project?.lastPathComponent == ".chat")
}
