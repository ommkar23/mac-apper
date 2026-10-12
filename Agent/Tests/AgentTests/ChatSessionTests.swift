// @frontmatter:start
// Tests workspace navigation and runtime attachment using service-backed chat histories.
// @frontmatter:end
import Foundation
import Testing

@testable import AgentApplication
@testable import AgentMacosClient
import AgentMacosClientModel

private typealias LocalWorkspaceStore = TestLocalWorkspaceStore
private typealias PiRPCEvent = AgentMacosClientModel.PiRPCEvent
private typealias PiRPCError = AgentMacosClientModel.PiRPCError

func writeSession(
	in project: URL, filename: String, prompt: String, answer: String, title: String? = nil
) throws -> URL {
	let directory = project.appendingPathComponent(".pi/sessions")
	try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
	let file = directory.appendingPathComponent(filename)
	var entries: [[String: Any]] = [
		[
			"type": "session", "version": 3, "id": UUID().uuidString, "cwd": project.path,
			"timestamp": "2026-09-17T00:00:00Z",
		],
		[
			"type": "message", "id": "user", "parentId": NSNull(),
			"message": ["role": "user", "content": prompt],
		],
		[
			"type": "message", "id": "answer", "parentId": "user",
			"message": ["role": "assistant", "content": [["type": "text", "text": answer]]],
		],
	]
	if let title {
		entries.append(["type": "session_info", "id": "title", "parentId": "answer", "name": title])
	}
	let text =
		try entries.map {
			String(decoding: try JSONSerialization.data(withJSONObject: $0), as: UTF8.self)
		}.joined(separator: "\n") + "\n"
	try text.write(to: file, atomically: true, encoding: .utf8)
	return file
}

@MainActor private final class NavigationRuntime: AgentMacosClientModel.AgentSessionRuntime {
	let customSessionDirectory: URL?
	init(customSessionDirectory: URL? = nil) {
		self.customSessionDirectory = customSessionDirectory
	}
	func sessionDirectory(in project: URL) -> URL {
		customSessionDirectory ?? project.appendingPathComponent(".pi/sessions", isDirectory: true)
	}
	var chatStarts = 0
	func startChat(in project: URL, sessionFile: URL, title: String?) async throws
		-> AsyncThrowingStream<PiRPCEvent, any Error>
	{
		chatStarts += 1
		return try await start(in: project, sessionFile: sessionFile, title: title)
	}
	var started: [(URL, URL, String?)] = []
	func start(in project: URL) async throws -> AsyncThrowingStream<PiRPCEvent, any Error> {
		throw PiRPCError.unavailable
	}
	func start(in project: URL, sessionFile: URL, title: String?) async throws -> AsyncThrowingStream<
		PiRPCEvent, any Error
	> {
		started.append((project, sessionFile, title))
		return AsyncThrowingStream {
			$0.yield(.settled)
			$0.finish()
		}
	}
	func prompt(_ message: String) async throws {}
	func abort() async throws {}
	func stop() async -> Bool { true }
}

@MainActor private final class AttachingRuntime: AgentMacosClientModel.AgentSessionRuntime {
	var attachedFiles: [URL] = []
	var stopped = 0
	var detached = 0
	private var continuation: AsyncThrowingStream<PiRPCEvent, any Error>.Continuation?
	func start(in project: URL) async throws -> AsyncThrowingStream<PiRPCEvent, any Error> {
		throw PiRPCError.unavailable
	}
	func start(in project: URL, sessionFile: URL, title: String?) async throws
		-> AsyncThrowingStream<PiRPCEvent, any Error>
	{ throw PiRPCError.unavailable }
	func attach(sessionFile: URL) async throws -> AsyncThrowingStream<PiRPCEvent, any Error>? {
		attachedFiles.append(sessionFile)
		return AsyncThrowingStream { continuation = $0 }
	}
	func emit(_ event: PiRPCEvent) { continuation?.yield(event) }
	func prompt(_ message: String) async throws {}
	func abort() async throws {}
	func stop() async -> Bool { stopped += 1; return true }
	func detach() async -> Bool { detached += 1; continuation?.finish(); return true }
}

@MainActor @Test func openingRunningSessionAttachesToPushWithoutStoppingAgent() async throws {
	let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
	defer { try? FileManager.default.removeItem(at: root) }
	let project = try ProjectScaffold.create(under: root)
	let file = try writeSession(
		in: project, filename: "active.jsonl", prompt: "First",
		answer: "First answer")
	let runtime = AttachingRuntime()
	let model = WorkspaceSession(
		runtime: runtime, workspaceStore: LocalWorkspaceStore(projectsRoot: root))
	await model.openSession(file, in: project)
	#expect(runtime.attachedFiles == [file])
	#expect(model.connected)
	runtime.emit(.textDelta(" continuing"))
	for _ in 0..<100 where model.messages.last?.text != "First answer continuing" {
		await Task.yield()
	}
	#expect(model.messages.last?.text == "First answer continuing")
	#expect(await model.shutdown())
	#expect(runtime.detached == 1)
	#expect(runtime.stopped == 0)
}

@MainActor @Test func navigatingAwayFromAttachedSessionDetachesWithoutAbortingPi() async throws {
	let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
	defer { try? FileManager.default.removeItem(at: root) }
	let project = try ProjectScaffold.create(under: root)
	let file = try writeSession(
		in: project, filename: "active.jsonl", prompt: "First",
		answer: "First answer")
	let runtime = AttachingRuntime()
	let model = WorkspaceSession(
		runtime: runtime, workspaceStore: LocalWorkspaceStore(projectsRoot: root))
	await model.openSession(file, in: project)
	await model.newChat()
	#expect(!model.connected)
	#expect(runtime.detached == 1)
	#expect(runtime.stopped == 0)
}

@MainActor @Test func workspaceUsesTheInjectedRuntimeSessionDirectory() async throws {
	let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
	defer { try? FileManager.default.removeItem(at: root) }
	let sessions = root.appendingPathComponent("custom-sessions", isDirectory: true)
	let runtime = NavigationRuntime(customSessionDirectory: sessions)
	let model = WorkspaceSession(
		runtime: runtime,
		workspaceStore: LocalWorkspaceStore(
			projectsRoot: root.appendingPathComponent("projects"), sessionDirectory: { _ in sessions }))
	await model.openBuiltInChat()
	model.idea = "First message"
	await model.submit()
	let file = try #require(model.sessionFile)
	#expect(file.deletingLastPathComponent().standardizedFileURL == sessions.standardizedFileURL)
	#expect(runtime.started.first?.1 == file)
	#expect(FileManager.default.fileExists(atPath: sessions.path))
	let project = try #require(model.project)
	#expect(FileManager.default.fileExists(atPath: project.path))
}

@MainActor @Test func projectChatNavigationDefersCreationAndResumesExactFile() async throws {
	let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
	defer { try? FileManager.default.removeItem(at: root) }
	let runtime = NavigationRuntime()
	let model = WorkspaceSession(
		runtime: runtime, workspaceStore: LocalWorkspaceStore(projectsRoot: root))
	await model.newChat(newApp: true)
	#expect(model.project == nil)
	#expect(!FileManager.default.fileExists(atPath: root.path))
	model.idea = "Build notes"
	await model.submit()
	let project = try #require(model.project)
	#expect(runtime.started.count == 1)
	let file = try writeSession(
		in: project, filename: "saved.jsonl", prompt: "Build notes", answer: "Welcome back",
		title: "Notes app")
	await model.openProject(project)
	#expect(model.chatTitle == "Notes app")
	#expect(model.messages.last?.text == "Welcome back")
	#expect(runtime.started.count == 1)
	model.idea = "Add search"
	await model.submit()
	#expect(runtime.started.last?.1.resolvingSymlinksInPath() == file.resolvingSymlinksInPath())
	#expect(runtime.started.last?.2 == nil)
	await model.newChat(newApp: false)
	#expect(model.project == project)
	#expect(model.messages.isEmpty)
	#expect(model.sessionFile == nil)
	#expect(try ChatSessionCatalog.discover(in: project).count == 1)
	model.idea = "Add tags"
	await model.submit()
	#expect(runtime.started.last?.0 == project)
	#expect(runtime.started.last?.1 != file)
	#expect(model.chatTitle == "Add tags")
	#expect(runtime.started.last?.2 == "Add tags")
	let other = try writeSession(
		in: project, filename: "other.jsonl", prompt: "Other request", answer: "Other answer",
		title: "Other chat")
	try FileManager.default.setAttributes(
		[.modificationDate: Date(timeIntervalSinceNow: 20)], ofItemAtPath: other.path)
	await model.openProject(project)
	#expect(model.chatTitle == "Other chat")
	#expect(model.sessions.count == 2)
	await model.openChat(file)
	#expect(model.chatTitle == "Notes app")
	#expect(model.messages.last?.text == "Welcome back")
	let count = runtime.started.count
	await model.newChat(newApp: true)
	#expect(model.project == nil)
	#expect(model.messages.isEmpty)
	#expect(runtime.started.count == count)
	#expect(try FileManager.default.contentsOfDirectory(atPath: root.path).count == 1)
}

@MainActor @Test func sidebarIncludesUnbuiltProjectsAndExactNestedSessions() async throws {
	let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
	defer { try? FileManager.default.removeItem(at: root) }
	let first = try ProjectScaffold.create(under: root)
	let second = try ProjectScaffold.create(under: root)
	let settings = second.appendingPathComponent("Info.plist")
	let info = try #require(NSMutableDictionary(contentsOf: settings))
	info["CFBundleDisplayName"] = "Timer"
	#expect(info.write(to: settings, atomically: true))
	let older = try writeSession(
		in: first, filename: "older.jsonl", prompt: "Build notes", answer: "First")
	_ = try writeSession(in: first, filename: "newer.jsonl", prompt: "Add search", answer: "Second")
	_ = try writeSession(in: second, filename: "other.jsonl", prompt: "Build timer", answer: "Timer")
	let model = WorkspaceSession(
		runtime: NavigationRuntime(), workspaceStore: LocalWorkspaceStore(projectsRoot: root))
	await model.refreshLibrary()
	#expect(model.library.count == 3)
	#expect(model.library.first?.isChatOnly == true)
	#expect(
		model.library.first(where: { $0.project.lastPathComponent == second.lastPathComponent })?.title
			== "Timer")
	#expect(
		model.library.first(where: { $0.project.lastPathComponent == first.lastPathComponent })?.title
			== "Generated App")
	#expect(
		model.library.first(where: {
			$0.project.resolvingSymlinksInPath().path == first.resolvingSymlinksInPath().path
		})?.sessions.count == 2)
	await model.openSession(older, in: first)
	#expect(model.project == first)
	#expect(model.sessionFile == older)
	#expect(model.messages.last?.text == "First")
	let discoveredProject = try #require(
		model.library.first(where: { $0.project.lastPathComponent == second.lastPathComponent })?
			.project)
	await model.openProject(discoveredProject)
	#expect(model.messages.last?.text == "Timer")
	let previous = model.sessionFile
	await model.openSession(older, in: second)
	#expect(model.sessionFile == previous)
}

@MainActor @Test func builtInChatDefersStorageAndNeverCreatesAnApp() async throws {
	let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
	defer { try? FileManager.default.removeItem(at: root) }
	let runtime = NavigationRuntime()
	let model = WorkspaceSession(
		runtime: runtime, workspaceStore: LocalWorkspaceStore(projectsRoot: root))
	await model.openBuiltInChat()
	#expect(model.isChatOnly)
	#expect(!FileManager.default.fileExists(atPath: root.path))
	model.idea = "Explain Swift actors"
	await model.submit()
	#expect(runtime.chatStarts == 1)
	let project = try #require(model.project)
	#expect(project.lastPathComponent == ".chat")
	#expect(
		!FileManager.default.fileExists(atPath: project.appendingPathComponent("Package.swift").path))
	let file = try writeSession(
		in: project, filename: "chat.jsonl", prompt: "Explain actors", answer: "Isolation")
	await model.newChat(newApp: true)
	#expect(!model.isChatOnly)
	await model.openBuiltInChat()
	#expect(model.sessionFile?.lastPathComponent == file.lastPathComponent)
	#expect(model.isChatOnly)
	await model.newChat()
	#expect(model.isChatOnly)
	#expect(model.messages.isEmpty)
}
