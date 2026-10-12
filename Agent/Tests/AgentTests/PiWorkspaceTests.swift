// @frontmatter:start
// Tests workspace submission, Pi session reuse, steering, and lifecycle state.
// @frontmatter:end
import Foundation
import Testing

@testable import AgentApplication
@testable import AgentMacosClient
import AgentMacosClientModel

private typealias LocalWorkspaceStore = TestLocalWorkspaceStore
private typealias PiRPCEvent = AgentMacosClientModel.PiRPCEvent
private typealias PiRPCError = AgentMacosClientModel.PiRPCError

@MainActor
private final class FixturePiRuntime: AgentMacosClientModel.AgentSessionRuntime,
	@unchecked Sendable
{
	private(set) var startedIn: URL?
	private(set) var startedWithSessionFile: URL?
	private(set) var prompts: [String] = []
	var events: [PiRPCEvent] = [
		.textDelta("Working"), .toolStarted(id: "1", name: "build", argumentsJSON: "{}"),
		.toolFinished(id: "1", name: "build", text: "Build verified", isError: false), .settled,
	]

	func start(in project: URL) async throws -> AsyncThrowingStream<PiRPCEvent, any Error> {
		startedIn = project
		return AsyncThrowingStream { continuation in
			for event in events { continuation.yield(event) }
			continuation.finish()
		}
	}
	func start(in project: URL, sessionFile: URL, title: String?) async throws -> AsyncThrowingStream<
		PiRPCEvent, any Error
	> {
		startedWithSessionFile = sessionFile
		if !FileManager.default.fileExists(atPath: sessionFile.path) {
			let header =
				try JSONSerialization.data(withJSONObject: [
					"type": "session", "version": 3, "cwd": project.path,
				]) + Data([10])
			try header.write(to: sessionFile)
		}
		return try await start(in: project)
	}
	func prompt(_ message: String) async throws { prompts.append(message) }
	func abort() async throws {}
	func stop() async -> Bool { true }
}

@MainActor @Test func workspaceCreatesProjectThenStartsPiInThatDirectory() async throws {
	let root = FileManager.default.temporaryDirectory.appendingPathComponent(
		UUID().uuidString, isDirectory: true)
	defer { try? FileManager.default.removeItem(at: root) }
	let pi = FixturePiRuntime()
	let workspace = WorkspaceSession(
		runtime: pi, workspaceStore: LocalWorkspaceStore(projectsRoot: root))
	workspace.idea = "Make a notes app"

	await workspace.submit()

	#expect(pi.startedIn == workspace.project)
	#expect(pi.prompts == ["Make a notes app"])
	#expect(workspace.project?.deletingLastPathComponent().path == root.path)
	#expect(workspace.state.transcript == "Working")
	#expect(workspace.state.status == "Completed")
	#expect(workspace.activity == "Pi session completed.")
	let firstProject = workspace.project
	workspace.idea = "Add search"
	await workspace.submit()
	#expect(workspace.project == firstProject)
	#expect(pi.prompts == ["Make a notes app", "Add search"])
}

@MainActor private final class PersistentPiRuntime: AgentMacosClientModel.AgentSessionRuntime {
	var continuation: AsyncThrowingStream<PiRPCEvent, any Error>.Continuation?
	var prompts: [String] = []
	var starts = 0
	func start(in project: URL) async throws -> AsyncThrowingStream<PiRPCEvent, any Error> {
		starts += 1
		return AsyncThrowingStream { continuation = $0 }
	}
	func start(in project: URL, sessionFile: URL, title: String?) async throws -> AsyncThrowingStream<
		PiRPCEvent, any Error
	> { try await start(in: project) }
	func prompt(_ message: String) async throws { prompts.append(message) }
	func abort() async throws {}
	func stop() async -> Bool {
		continuation?.finish()
		return true
	}
}

@MainActor @Test func persistentSessionSettlesAndAcceptsSteeringAndFollowUp() async throws {
	let root = FileManager.default.temporaryDirectory.appendingPathComponent(
		UUID().uuidString, isDirectory: true)
	defer { try? FileManager.default.removeItem(at: root) }
	let pi = PersistentPiRuntime()
	let workspace = WorkspaceSession(
		runtime: pi, workspaceStore: LocalWorkspaceStore(projectsRoot: root))
	workspace.idea = "Notes"
	let running = Task { await workspace.submit() }
	for _ in 0..<200 where pi.prompts.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
	#expect(pi.prompts == ["Notes"])
	let firstProject = workspace.project
	workspace.idea = "Use blue"
	await workspace.submit()
	#expect(pi.prompts == ["Notes", "Use blue"])
	pi.continuation?.yield(.settled)
	for _ in 0..<100 where workspace.busy { try await Task.sleep(for: .milliseconds(10)) }
	#expect(!workspace.busy)
	workspace.idea = "Add search"
	// Do not await a new event loop if the implementation wrongly starts one.
	let followUp = Task { await workspace.submit() }
	for _ in 0..<100 where pi.prompts.count < 3 { try await Task.sleep(for: .milliseconds(10)) }
	#expect(pi.starts == 1)
	#expect(workspace.project == firstProject)
	#expect(pi.prompts == ["Notes", "Use blue", "Add search"])
	pi.continuation?.yield(.settled)
	pi.continuation?.finish()
	await running.value
	await followUp.value
}

@MainActor @Test(arguments: ["ordinary", "recovered", "aborted", "exhausted"])
func piRPCLifecycleKeepsClientBusyUntilSettled(_ outcome: String) async throws {
	let root = FileManager.default.temporaryDirectory.appendingPathComponent(
		UUID().uuidString, isDirectory: true)
	defer { try? FileManager.default.removeItem(at: root) }
	let pi = PersistentPiRuntime()
	let workspace = WorkspaceSession(
		runtime: pi, workspaceStore: LocalWorkspaceStore(projectsRoot: root))
	workspace.idea = "Offline lifecycle fixture"
	let running = Task { await workspace.submit() }
	defer { pi.continuation?.finish() }
	for _ in 0..<200 where pi.prompts.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
	#expect(pi.prompts.count == 1)
	var parser = PiRPCParser()
	func deliver(_ record: String) throws {
		for event in try parser.feed(Data((record + "\n").utf8)) {
			switch event {
			case .settled: pi.continuation?.yield(.settled)
			case .textDelta(let text): pi.continuation?.yield(.textDelta(text))
			case .toolStarted(let id, let name, let arguments):
				pi.continuation?.yield(.toolStarted(id: id, name: name, argumentsJSON: arguments))
			case .toolFinished(let id, let name, let text, let isError):
				pi.continuation?.yield(.toolFinished(id: id, name: name, text: text, isError: isError))
			case .notification(let text): pi.continuation?.yield(.notification(text))
			default: Issue.record("Unexpected lifecycle fixture event")
			}
		}
	}
	try deliver("{\"type\":\"agent_end\",\"messages\":[],\"willRetry\":\(outcome != "ordinary")}")
	try deliver(#"{"type":"extension_ui_request","method":"notify","message":"end observed"}"#)
	for _ in 0..<200 where !workspace.state.liveDetails.contains("end observed") {
		try await Task.sleep(for: .milliseconds(10))
	}
	#expect(workspace.state.liveDetails.contains("end observed"))
	#expect(workspace.busy)
	#expect(!workspace.canNavigate)
	#expect(workspace.state.status != "Completed")
	if outcome == "recovered" {
		try deliver(#"{"type":"auto_retry_start","attempt":1,"maxAttempts":3,"delayMs":2000}"#)
		try deliver(
			#"{"type":"message_update","assistantMessageEvent":{"type":"text_delta","delta":"Recovered"}}"#
		)
		try deliver(#"{"type":"tool_execution_start","toolCallId":"1","toolName":"build","args":{}}"#)
		try deliver(
			#"{"type":"tool_execution_end","toolCallId":"1","toolName":"build","result":{"content":[{"type":"text","text":"Built"}]},"isError":false}"#
		)
	}
	if outcome == "aborted" || outcome == "exhausted" {
		try deliver(#"{"type":"auto_retry_end","success":false,"attempt":3}"#)
	}
	try deliver(#"{"type":"agent_end","messages":[],"willRetry":false}"#)
	try deliver(
		#"{"type":"extension_ui_request","method":"notify","message":"continuation observed"}"#)
	for _ in 0..<200 where !workspace.state.liveDetails.contains("continuation observed") {
		try await Task.sleep(for: .milliseconds(10))
	}
	#expect(workspace.state.liveDetails.contains("continuation observed"))
	#expect(workspace.busy)
	if outcome == "recovered" {
		#expect(workspace.state.transcript == "Recovered")
		#expect(workspace.state.liveDetails.contains("build · completed · Built"))
	}
	try deliver("{\"type\":\"agent_settled\",\"aborted\":\(outcome == "aborted")}")
	for _ in 0..<200 where workspace.busy { try await Task.sleep(for: .milliseconds(10)) }
	#expect(!workspace.busy)
	#expect(workspace.canNavigate)
	#expect(workspace.state.status == "Completed")
	pi.continuation?.finish()
	await running.value
}

@MainActor @Test func renameSanitizesThenRunsTheModelFreePackagingCommand() async throws {
	let root = FileManager.default.temporaryDirectory.appendingPathComponent(
		UUID().uuidString, isDirectory: true)
	defer { try? FileManager.default.removeItem(at: root) }
	let project = try ProjectScaffold.create(under: root)
	try FileManager.default.createDirectory(
		at: project.appendingPathComponent(".pi/sessions", isDirectory: true),
		withIntermediateDirectories: true)
	let pi = FixturePiRuntime()
	pi.events = [.notification("MAC_APPER_RENAMED:UGFwZXIgUmVhZGVy")]
	let workspace = WorkspaceSession(
		runtime: pi, workspaceStore: LocalWorkspaceStore(projectsRoot: root))
	#expect(
		project.resolvingSymlinksInPath().deletingLastPathComponent()
			== root.resolvingSymlinksInPath().standardizedFileURL)
	_ = try ChatSessionCatalog.discover(in: project)
	await workspace.openProject(project)

	#expect(await workspace.renameApplication(to: "  Paper/Reader.app "))

	#expect(pi.startedIn == project)
	#expect(
		pi.startedWithSessionFile?.deletingLastPathComponent()
			== project.appendingPathComponent(".pi/sessions", isDirectory: true))
	#expect(pi.prompts == ["/mac-apper-rename UGFwZXIgUmVhZGVy"])
	#expect(workspace.activity == "App renamed to Paper Reader.")
	#expect(!workspace.renaming)
}
