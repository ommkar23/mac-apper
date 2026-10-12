// @frontmatter:start
// Tests presentation launch and rename actions across navigation and failures.
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

@MainActor private final class ActionRuntime: AgentMacosClientModel.AgentSessionRuntime {
	var starts = 0
	func start(in project: URL) async throws -> AsyncThrowingStream<PiRPCEvent, any Error> {
		starts += 1; throw PiRPCError.unavailable
	}
	func start(in project: URL, sessionFile: URL, title: String?) async throws -> AsyncThrowingStream<
		PiRPCEvent, any Error
	> { try await start(in: project) }
	func prompt(_ message: String) async throws {}
	func abort() async throws {}
	func stop() async -> Bool { true }
}
@MainActor private final class DelayedLaunch: WorkspaceHostActions {
	var pending: CheckedContinuation<Void, any Error>?
	var url: URL?
	func launchApplication(at url: URL) async throws {
		self.url = url
		try await withCheckedThrowingContinuation { pending = $0 }
	}
	func openCodebaseInZed(at url: URL) async throws { throw PiRPCError.unavailable }
	func copyDiagnostics(_ text: String) throws { throw PiRPCError.unavailable }
	func revealLogs(at url: URL) throws { throw PiRPCError.unavailable }
}

@MainActor @Test func presentationLaunchFailureDoesNotLeakAcrossNavigation() async throws {
	let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
	defer { try? FileManager.default.removeItem(at: root) }
	let project = try ProjectScaffold.create(under: root)
	let contents = root.appendingPathComponent(
		"output/\(project.lastPathComponent)/Notes.app/Contents")
	try FileManager.default.createDirectory(
		at: contents.appendingPathComponent("MacOS"), withIntermediateDirectories: true)
	let executable = contents.appendingPathComponent("MacOS/ProductionApp")
	try Data().write(to: executable)
	try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
	try PropertyListSerialization.data(
		fromPropertyList: ["CFBundleDisplayName": "Notes"], format: .xml, options: 0
	).write(to: contents.appendingPathComponent("Info.plist"))
	let session = WorkspaceSession(
		runtime: ActionRuntime(), workspaceStore: LocalWorkspaceStore(projectsRoot: root))
	await session.openProject(project)
	let host = DelayedLaunch()
	let model = WorkspacePresentation(session: session, host: host)
	await model.refresh()
	#expect(model.canLaunch)
	let launch = Task { await model.launchCurrentApp() }
	for _ in 0..<100 where host.pending == nil { await Task.yield() }
	#expect(host.pending != nil)
	host.pending?.resume(throwing: PiRPCError.unavailable)
	host.pending = nil
	await launch.value
	#expect(model.footerText.contains("Couldn’t launch Notes"))
	let stale = Task { await model.launchCurrentApp() }
	for _ in 0..<100 where host.pending == nil { await Task.yield() }
	await model.newChat(newApp: true)
	host.pending?.resume(throwing: PiRPCError.unavailable)
	host.pending = nil
	await stale.value
	#expect(model.launchError.isEmpty)
	#expect(!model.canLaunch)
}

@MainActor @Test func presentationRenameFailureKeepsDestinationAndRejectsForeignProject()
	async throws
{
	let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
	defer { try? FileManager.default.removeItem(at: root) }
	let project = try ProjectScaffold.create(under: root)
	let runtime = ActionRuntime()
	let session = WorkspaceSession(
		runtime: runtime, workspaceStore: LocalWorkspaceStore(projectsRoot: root))
	await session.openProject(project)
	let model = WorkspacePresentation(session: session)
	let app = BuiltApp(
		name: "Notes", projectName: project.lastPathComponent,
		bundleURL: project.appendingPathComponent("dist/Production.app"))
	model.beginRename(app)
	model.renameDraft = "New Notes"
	await model.confirmRename()
	#expect(runtime.starts == 1)
	#expect(!model.renameError.isEmpty)
	#expect(model.sheet?.id == "rename:" + app.bundleURL.path)
	#expect(!model.renameSubmitting)
	model.beginRename(
		BuiltApp(
			name: "Foreign", projectName: "outside",
			bundleURL: root.deletingLastPathComponent().appendingPathComponent(
				"outside/dist/Production.app")))
	await model.confirmRename()
	#expect(runtime.starts == 1)
	#expect(session.project == project)
	#expect(!model.renameError.isEmpty)
}
