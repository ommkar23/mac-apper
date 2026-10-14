// @frontmatter:start
// Tests client workspace state against injected store snapshots and prepared paths.
// @frontmatter:end
import Foundation
import Scenario
import Testing
@testable import AgentMacosClient
import AgentMacosClientModel

private typealias PiRPCEvent = AgentMacosClientModel.PiRPCEvent
private typealias PiRPCError = AgentMacosClientModel.PiRPCError
private typealias WorkspaceGroup = AgentMacosClientModel.WorkspaceGroup
private typealias WorkspaceOpenResult = AgentMacosClientModel.WorkspaceOpenResult
private typealias WorkspacePreparedSession = AgentMacosClientModel.WorkspacePreparedSession
private typealias ChatSessionSummary = AgentMacosClientModel.ChatSessionSummary

@MainActor private final class WorkspaceStoreFixture: AgentMacosClientModel.WorkspaceStore {
	var groups: [WorkspaceGroup] = []
	var prepared: WorkspacePreparedSession?
	private(set) var preparation: [String] = []

	func loadLibrary() async throws -> [WorkspaceGroup] { groups }
	func loadProject(_ project: URL, session: URL?) async throws -> WorkspaceOpenResult {
		.init(project: project, sessions: [], history: nil, isChatOnly: false)
	}
	func loadSessions(in project: URL) async throws -> [ChatSessionSummary] { [] }
	func loadChatProject() async throws -> WorkspaceOpenResult? { nil }
	func prepareChatSession(request: String) async throws -> WorkspacePreparedSession {
		try next("chat")
	}
	func prepareCreateProject(request: String) async throws -> WorkspacePreparedSession {
		try next("createProject")
	}
	func prepareCreateSession(in project: URL, request: String) async throws
		-> WorkspacePreparedSession
	{
		try next("createSession")
	}
	func resumeSession(in project: URL, sessionFile: URL) async throws
		-> WorkspacePreparedSession
	{
		try next("resume")
	}
	private func next(_ operation: String) throws -> WorkspacePreparedSession {
		preparation.append(operation)
		return try #require(prepared)
	}
	func validatePreview(relativePath: String, project: URL) async throws -> URL? { nil }
	func diagnosticDirectory(for project: URL) async throws -> URL {
		project.appendingPathComponent(".pi/sessions")
	}
}

@MainActor private final class StoreRuntimeFixture: AgentMacosClientModel.AgentSessionRuntime {
	var abortCount = 0
	let events: [PiRPCEvent]
	init(events: [PiRPCEvent] = []) { self.events = events }
	func start(in project: URL) async throws -> AsyncThrowingStream<PiRPCEvent, any Error> {
		throw PiRPCError.unavailable
	}
	func start(in project: URL, sessionFile: URL, title: String?) async throws -> AsyncThrowingStream<
		PiRPCEvent, any Error
	> { throw PiRPCError.unavailable }
	func start(agentID: String, in project: URL, sessionFile: URL, title: String?, firstRequest: Bool)
		async throws -> AsyncThrowingStream<PiRPCEvent, any Error>
	{
		AsyncThrowingStream { continuation in
			for event in events { continuation.yield(event) }
			continuation.finish()
		}
	}
	func prompt(_ message: String) async throws {}
	func abort() async throws { abortCount += 1 }
	func stop() async -> Bool { true }
}

@MainActor @Test func cancellationAbortsWithoutPreparingWorkspace() async {
	let runtime = StoreRuntimeFixture()
	let workspace = WorkspaceSession(runtime: runtime)
	#expect(await workspace.cancel())
	#expect(runtime.abortCount == 1)
	#expect(workspace.state.status == "Cancelled")
}

@MainActor @Test func newAppPageIsDistinctFromEmptyChatAndExistingProject() async throws {
	let store = WorkspaceStoreFixture()
	let project = URL(fileURLWithPath: "/service/\(UUID().uuidString)")
	store.prepared = .init(
		project: project, sessionFile: project.appendingPathComponent(".pi/sessions/chat.jsonl"),
		title: "Build notes", isNew: true, creatingApp: true)
	let model = WorkspaceSession(
		runtime: StoreRuntimeFixture(events: [.settled]), workspaceStore: store)
	#expect(model.isNewAppPage)
	model.idea = "Draft request"
	#expect(model.isNewAppPage)
	await model.openBuiltInChat()
	#expect(!model.isNewAppPage)
	await model.newChat(newApp: true)
	#expect(model.isNewAppPage)
	model.idea = "Build notes"
	await model.submit()
	#expect(!model.isNewAppPage)
	await model.newChat()
	#expect(model.messages.isEmpty)
	#expect(!model.isNewAppPage)
	await model.newChat(newApp: true)
	#expect(model.isNewAppPage)
}

@MainActor @Test func workspaceLoadsItsLibraryFromTheInjectedStore() async throws {
	let store = WorkspaceStoreFixture()
	let project = URL(fileURLWithPath: "/service/project")
	store.groups = [
		.init(project: project, title: "Service App", isChatOnly: false, app: nil, sessions: [])
	]
	let workspace = WorkspaceSession(runtime: StoreRuntimeFixture(), workspaceStore: store)

	await workspace.refreshLibrary()

	#expect(workspace.library.map(\.title) == ["Service App"])
}

@MainActor @Test func workspaceRoutesChatAndExistingCreateSessionsToDistinctStoreMethods()
	async throws
{
	let store = WorkspaceStoreFixture()
	let chat = URL(fileURLWithPath: "/service/.chat")
	store.prepared = .init(
		project: chat, sessionFile: chat.appendingPathComponent("chat.jsonl"),
		title: "Chat", isNew: true, creatingApp: false)
	let chatWorkspace = WorkspaceSession(
		runtime: StoreRuntimeFixture(events: [.settled]), workspaceStore: store)
	chatWorkspace.selectAgent("chat")
	chatWorkspace.idea = "Hello"
	await chatWorkspace.submit()
	#expect(store.preparation == ["chat"])

	let project = URL(fileURLWithPath: "/service/\(UUID().uuidString)")
	store.prepared = .init(
		project: project, sessionFile: project.appendingPathComponent("new.jsonl"),
		title: "Next", isNew: true, creatingApp: false)
	let createWorkspace = WorkspaceSession(
		runtime: StoreRuntimeFixture(events: [.settled]), workspaceStore: store)
	await createWorkspace.openProject(project)
	createWorkspace.idea = "Continue"
	await createWorkspace.submit()
	#expect(store.preparation == ["chat", "createSession"])
}

@MainActor @Test func workspaceUsesServicePreparedPathsWithoutCreatingClientFiles() async throws {
	let store = WorkspaceStoreFixture()
	let project = try ProjectTemporaryDirectory.root().appendingPathComponent(UUID().uuidString)
	let session = project.appendingPathComponent(".pi/sessions/service.jsonl")
	store.prepared = .init(
		project: project, sessionFile: session, title: "Build it", isNew: true, creatingApp: true)
	let runtime = StoreRuntimeFixture(events: [.settled])
	let workspace = WorkspaceSession(runtime: runtime, workspaceStore: store)
	workspace.idea = "Build it"

	await workspace.submit()

	#expect(store.preparation == ["createProject"])
	#expect(workspace.project == project)
	#expect(workspace.sessionFile == session)
	#expect(!FileManager.default.fileExists(atPath: project.path))
}
