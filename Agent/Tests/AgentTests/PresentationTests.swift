// @frontmatter:start
// Tests presentation controls, host actions, composer state, and refresh lifecycle.
// @frontmatter:end
import Foundation
import Testing
@testable import AgentApplication
@testable import AgentMacosClient
import AgentMacosClientModel

private typealias LocalWorkspaceStore = TestLocalWorkspaceStore
private typealias PiRPCEvent = AgentMacosClientModel.PiRPCEvent
private typealias PiRPCError = AgentMacosClientModel.PiRPCError
private typealias BuiltApp = AgentMacosClientModel.BuiltApp

@MainActor private final class PresentationRuntime: AgentMacosClientModel.AgentSessionRuntime {
	func start(in project: URL) async throws -> AsyncThrowingStream<PiRPCEvent, any Error> {
		throw PiRPCError.unavailable
	}
	func start(in project: URL, sessionFile: URL, title: String?) async throws -> AsyncThrowingStream<
		PiRPCEvent, any Error
	> { throw PiRPCError.unavailable }
	func prompt(_ message: String) async throws {}
	func abort() async throws {}
	func stop() async -> Bool { true }
}

@MainActor private final class RecordingHost: WorkspaceHostActions {
	var copied = ""
	var revealed: URL?
	var launched: URL?
	var openedCodebase: URL?
	func launchApplication(at url: URL) async throws { launched = url; throw PiRPCError.unavailable }
	func openCodebaseInZed(at url: URL) async throws { openedCodebase = url }
	func copyDiagnostics(_ text: String) throws { copied = text }
	func revealLogs(at url: URL) throws { revealed = url }
}

@MainActor @Test func presentationHostActionsAndRefreshLifecycle() async throws {
	let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
	defer { try? FileManager.default.removeItem(at: root) }
	let project = try ProjectScaffold.create(under: root)
	let session = WorkspaceSession(
		runtime: PresentationRuntime(), workspaceStore: LocalWorkspaceStore(projectsRoot: root))
	await session.openProject(project)
	let host = RecordingHost()
	let model = WorkspacePresentation(session: session, host: host)
	model.copyDiagnostics()
	#expect(host.copied == session.safeDiagnostics)
	await model.revealLogs()
	#expect(host.revealed?.path == project.appendingPathComponent(".pi/sessions").path)
	await model.openCodebaseInZed()
	#expect(host.openedCodebase == project)
	await model.newChat(newApp: true)
	#expect(!model.canOpenCodebase)
	let refresh = Task { await model.runRefreshLoop(interval: .milliseconds(10)) }
	for _ in 0..<100 where !model.refreshing { await Task.yield() }
	#expect(model.refreshing)
	refresh.cancel()
	await refresh.value
	#expect(!model.refreshing)
	let app = BuiltApp(
		name: "Notes", projectName: project.lastPathComponent,
		bundleURL: project.appendingPathComponent("dist/Production.app"))
	model.beginRename(app)
	#expect(model.sheet?.id == "rename:" + app.bundleURL.path)
	#expect(model.renameDraft == "Notes")
	model.renameDraft = " "
	#expect(!model.canRename)
	model.cancelRename()
	#expect(model.sheet == nil)
}

@MainActor @Test func presentationOwnsComposerAndNavigation() async throws {
	let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
	defer { try? FileManager.default.removeItem(at: root) }
	let session = WorkspaceSession(
		runtime: PresentationRuntime(), workspaceStore: LocalWorkspaceStore(projectsRoot: root))
	let model = WorkspacePresentation(session: session)
	#expect(model.isInitialComposer)
	#expect(!model.canSendMessage)
	session.idea = " \n "
	#expect(!model.canSendMessage)
	session.idea = "Hello"
	#expect(model.canSendMessage)
	session.idea = String(repeating: "a", count: 65_537)
	#expect(!model.canSendMessage)
	#expect(model.composerPlaceholder == "What would you like to build?")
	await session.openBuiltInChat()
	#expect(model.composerPlaceholder == "What would you like to talk about?")
	#expect(!model.canOpenCodebase)
	let group = root.appendingPathComponent("group")
	model.toggleGroup(group)
	#expect(model.collapsedGroups.contains(group))
	model.toggleGroup(group)
	#expect(model.collapsedGroups.isEmpty)
	await model.showDiagnostics()
	#expect(model.diagnosticsPresented)
	model.dismissDiagnostics()
	#expect(!model.diagnosticsPresented)
}
