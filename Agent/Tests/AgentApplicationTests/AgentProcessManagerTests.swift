// @frontmatter:start
// Tests server-owned session lifetime, event replay, subscriptions, and scoped operations.
// @frontmatter:end
import Foundation
import Testing

@testable import AgentApplication

@MainActor private final class ManagedRuntimeFixture: PiSessionRuntime {
	private var continuation: AsyncThrowingStream<PiRPCEvent, any Error>.Continuation?
	private(set) var prompts: [String] = []
	private(set) var startCount = 0
	private(set) var stopped = false

	func start(in project: URL) async throws -> AsyncThrowingStream<PiRPCEvent, any Error> {
		throw PiRPCError.unavailable
	}

	func start(in project: URL, sessionFile: URL, title: String?) async throws
		-> AsyncThrowingStream<PiRPCEvent, any Error>
	{
		startCount += 1
		return AsyncThrowingStream { continuation in self.continuation = continuation }
	}

	func start(
		agentID: String, in project: URL, sessionFile: URL, title: String?, firstRequest: Bool
	) async throws -> AsyncThrowingStream<PiRPCEvent, any Error> {
		try await start(in: project, sessionFile: sessionFile, title: title)
	}

	func prompt(_ message: String) async throws { prompts.append(message) }
	func abort() async throws {}
	func stop() async -> Bool { stopped = true; continuation?.finish(); return true }
	func emit(_ event: PiRPCEvent) { continuation?.yield(event) }
	func finish() { continuation?.finish() }
}

@MainActor private func issue(
	_ request: AgentSessionStartRequest, to preparations: SessionPreparationRegistry
) throws {
	try preparations.issue(
		.init(
			project: URL(fileURLWithPath: request.projectPath),
			sessionFile: URL(fileURLWithPath: request.sessionFilePath),
			title: request.title ?? "", isNew: request.title != nil,
			creatingApp: request.firstRequest), agentID: request.agentID)
}

@MainActor @Test func managerKeepsRunningAndBuffersEventsWithoutAClientListener() async throws {
	let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
	defer { try? FileManager.default.removeItem(at: root) }
	let project = root.appendingPathComponent(UUID().uuidString.lowercased())
	let session = project.appendingPathComponent(".pi/sessions/session-1.jsonl")
	try FileManager.default.createDirectory(
		at: session.deletingLastPathComponent(), withIntermediateDirectories: true)
	let runtime = ManagedRuntimeFixture()
	let preparations = SessionPreparationRegistry()
	let manager = AgentProcessManager(projectsRoot: root, preparations: preparations) { _ in runtime }
	let request = try AgentSessionStartRequest(
		sessionID: "session-1", agentID: "create", projectPath: project.path,
		sessionFilePath: session.path, title: "Build", firstRequest: true)
	try issue(request, to: preparations)
	_ = try await manager.start(request)
	#expect(try manager.projectPath(sessionID: "session-1") == project.path)
	try await manager.prompt(.init(sessionID: "session-1", message: "Build it"))
	runtime.emit(.textDelta("Working"))
	runtime.emit(.settled)
	runtime.emit(.notification("after-settled"))

	var batch = try manager.history(sessionID: "session-1", cursor: 0)
	for _ in 0..<100 where batch.events.count < 3 {
		await Task.yield()
		batch = try manager.history(sessionID: "session-1", cursor: 0)
	}
	#expect(runtime.prompts == ["Build it"])
	#expect(
		batch.events.map(\.event) == [
			.textDelta("Working"), .settled, .notification("after-settled"),
		])
	#expect(batch.nextCursor == 3)
}

@MainActor @Test func managerPersistsAndPagesCompleteHistoryAcrossReattach() async throws {
	let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
	defer { try? FileManager.default.removeItem(at: root) }
	let project = root.appendingPathComponent(UUID().uuidString.lowercased())
	let session = project.appendingPathComponent(".pi/sessions/session-1.jsonl")
	try FileManager.default.createDirectory(
		at: session.deletingLastPathComponent(),
		withIntermediateDirectories: true)
	let runtime = ManagedRuntimeFixture()
	let request = try AgentSessionStartRequest(
		sessionID: "session-1", agentID: "create",
		projectPath: project.path, sessionFilePath: session.path, title: nil, firstRequest: false)
	let preparations = SessionPreparationRegistry()
	let first = AgentProcessManager(
		projectsRoot: root, eventLimit: 2, preparations: preparations
	) { _ in runtime }
	try issue(request, to: preparations)
	_ = try await first.start(request)
	var received: [Int] = []
	var finished = false
	let (token, boundary) = try first.subscribe(
		sessionID: "session-1",
		observer: { received.append($0.sequence) }, onFinished: { _ in finished = true })
	#expect(boundary == 0)
	for index in 0..<140 { runtime.emit(.textDelta("event-\(index)")) }
	for _ in 0..<1_000 where received.count < 140 {
		try await Task.sleep(for: .milliseconds(10))
	}
	#expect(received == Array(0..<140))
	first.unsubscribe(sessionID: "session-1", id: token)
	#expect(!finished)
	let replayPreparations = SessionPreparationRegistry()
	let replay = AgentProcessManager(
		projectsRoot: root, eventLimit: 2, preparations: replayPreparations
	) { _ in ManagedRuntimeFixture() }
	try issue(request, to: replayPreparations)
	#expect(try await replay.start(request) == 140)
	var cursor = 0
	var history: [SequencedAgentServiceEvent] = []
	while cursor < 140 {
		let page = try replay.history(sessionID: "session-1", cursor: cursor)
		guard
			!page.events.isEmpty
		else { throw AgentProcessManagerError.staleCursor }
		#expect(page.events.count <= 128 && page.nextCursor > cursor)
		history += page.events
		cursor = page.nextCursor
	}
	#expect(history.map(\.sequence) == Array(0..<140))
}

@MainActor @Test func managerBoundsLiveSubscribersWithoutLimitingHistory() async throws {
	let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
	defer { try? FileManager.default.removeItem(at: root) }
	let project = root.appendingPathComponent(".chat")
	let session = project.appendingPathComponent(".pi/sessions/session-1.jsonl")
	try FileManager.default.createDirectory(
		at: session.deletingLastPathComponent(),
		withIntermediateDirectories: true)
	let preparations = SessionPreparationRegistry()
	let manager = AgentProcessManager(
		projectsRoot: root, preparations: preparations
	) { _ in ManagedRuntimeFixture() }
	let request = try AgentSessionStartRequest(
		sessionID: "session-1", agentID: "chat",
		projectPath: project.path, sessionFilePath: session.path, title: nil, firstRequest: false)
	try issue(request, to: preparations)
	_ = try await manager.start(request)
	for _ in 0..<32 { _ = try manager.subscribe(sessionID: "session-1", observer: { _ in }) }
	#expect(throws: AgentProcessManagerError.invalidScope) {
		try manager.subscribe(sessionID: "session-1", observer: { _ in })
	}
	#expect(try manager.history(sessionID: "session-1", cursor: 0).events.isEmpty)
}

@MainActor @Test func managerAllowsSessionReattachWithoutRestartingPi() async throws {
	let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
	defer { try? FileManager.default.removeItem(at: root) }
	let project = root.appendingPathComponent(UUID().uuidString.lowercased())
	let session = project.appendingPathComponent(".pi/sessions/session-1.jsonl")
	try FileManager.default.createDirectory(
		at: session.deletingLastPathComponent(), withIntermediateDirectories: true)
	let runtime = ManagedRuntimeFixture()
	let preparations = SessionPreparationRegistry()
	let manager = AgentProcessManager(projectsRoot: root, preparations: preparations) { _ in runtime }
	let request = try AgentSessionStartRequest(
		sessionID: "session-1", agentID: "create", projectPath: project.path,
		sessionFilePath: session.path, title: "Build", firstRequest: true)
	try issue(request, to: preparations)
	_ = try await manager.start(request)
	runtime.emit(.textDelta("still running"))
	for _ in 0..<100
	where (try? manager.history(sessionID: "session-1", cursor: 0).events.isEmpty) == true {
		await Task.yield()
	}
	let cursor = try await manager.start(
		.init(
			sessionID: "session-1", agentID: "create", projectPath: project.path,
			sessionFilePath: session.path, title: nil, firstRequest: false))
	#expect(runtime.startCount == 1)
	#expect(cursor == 1)
}

@MainActor @Test func stoppedSessionCanStartAgain() async throws {
	let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
	defer { try? FileManager.default.removeItem(at: root) }
	let project = root.appendingPathComponent(UUID().uuidString.lowercased())
	let session = project.appendingPathComponent(".pi/sessions/session-1.jsonl")
	try FileManager.default.createDirectory(
		at: session.deletingLastPathComponent(), withIntermediateDirectories: true)
	let runtime = ManagedRuntimeFixture()
	let preparations = SessionPreparationRegistry()
	let manager = AgentProcessManager(projectsRoot: root, preparations: preparations) { _ in runtime }
	let request = try AgentSessionStartRequest(
		sessionID: "session-1", agentID: "create", projectPath: project.path,
		sessionFilePath: session.path, title: nil, firstRequest: false)
	try issue(request, to: preparations)
	_ = try await manager.start(request)
	var finished = false
	_ = try manager.subscribe(
		sessionID: "session-1", observer: { _ in },
		onFinished: { _ in finished = true })
	_ = try await manager.stop(sessionID: "session-1")
	#expect(finished)
	#expect(throws: AgentProcessManagerError.unknownSession) {
		try manager.projectPath(sessionID: "session-1")
	}
	try issue(request, to: preparations)
	_ = try await manager.start(request)
	#expect(runtime.startCount == 2)
}

@MainActor @Test func terminalSessionResumesPiAndRetainsEarlierHistory() async throws {
	let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
	defer { try? FileManager.default.removeItem(at: root) }
	let project = root.appendingPathComponent(".chat")
	let session = project.appendingPathComponent(".pi/sessions/session-1.jsonl")
	try FileManager.default.createDirectory(
		at: session.deletingLastPathComponent(),
		withIntermediateDirectories: true)
	let runtime = ManagedRuntimeFixture()
	let preparations = SessionPreparationRegistry()
	let manager = AgentProcessManager(projectsRoot: root, preparations: preparations) { _ in runtime }
	let request = try AgentSessionStartRequest(
		sessionID: "session-1", agentID: "chat",
		projectPath: project.path, sessionFilePath: session.path, title: nil, firstRequest: false)
	try issue(request, to: preparations)
	_ = try await manager.start(request)
	runtime.emit(.textDelta("before"))
	runtime.finish()
	for _ in 0..<100 where !(try manager.history(sessionID: "session-1", cursor: 0)).terminal {
		await Task.yield()
	}
	#expect(try manager.history(sessionID: "session-1", cursor: 0).terminal)
	try issue(request, to: preparations)
	#expect(try await manager.start(request) == 1)
	#expect(runtime.startCount == 2)
	#expect(
		try manager.history(sessionID: "session-1", cursor: 0).events.map(\.event)
			== [.textDelta("before")])
}

@MainActor @Test func managerStartsOnlySessionsPreparedByTheService() async throws {
	let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
	defer { try? FileManager.default.removeItem(at: root) }
	let preparations = SessionPreparationRegistry()
	let workspace = WorkspaceDataManager(projectsRoot: root, preparations: preparations)
	let runtime = ManagedRuntimeFixture()
	let manager = AgentProcessManager(projectsRoot: root, preparations: preparations) { _ in runtime }
	guard
		case .prepared(let prepared) = try await workspace.handle(
			.prepareChatSession(request: "Talk"))
	else {
		Issue.record("Missing preparation")
		return
	}
	let sessionID = URL(fileURLWithPath: prepared.sessionFilePath).deletingPathExtension()
		.lastPathComponent
	let request = try AgentSessionStartRequest(
		sessionID: sessionID, agentID: "chat", projectPath: prepared.projectPath,
		sessionFilePath: prepared.sessionFilePath, title: prepared.title, firstRequest: false)
	let forgedID = UUID().uuidString
	let forged = try AgentSessionStartRequest(
		sessionID: forgedID, agentID: "chat", projectPath: prepared.projectPath,
		sessionFilePath: URL(fileURLWithPath: prepared.sessionFilePath)
			.deletingLastPathComponent().appendingPathComponent("\(forgedID).jsonl").path,
		title: "Forged", firstRequest: false)
	await #expect(throws: AgentProcessManagerError.invalidScope) {
		_ = try await manager.start(forged)
	}
	await #expect(throws: AgentProcessManagerError.invalidScope) {
		_ = try await manager.start(
			.init(
				sessionID: sessionID, agentID: "chat", projectPath: prepared.projectPath,
				sessionFilePath: prepared.sessionFilePath, title: prepared.title, firstRequest: true))
	}
	#expect(runtime.startCount == 0)
	_ = try await manager.start(request)
	#expect(runtime.startCount == 1)
	_ = try await manager.stop(sessionID: sessionID)
	await #expect(throws: AgentProcessManagerError.invalidScope) {
		_ = try await manager.start(request)
	}
	let sessionFile = URL(fileURLWithPath: prepared.sessionFilePath)
	let header =
		try JSONSerialization.data(withJSONObject: [
			"type": "session", "version": 3, "cwd": prepared.projectPath,
		]) + Data([10])
	try header.write(to: sessionFile)
	let resumed = try await workspace.handle(
		.resumeSession(
			projectPath: prepared.projectPath, sessionFilePath: prepared.sessionFilePath))
	guard
		case .prepared(let resumedSession) = resumed
	else {
		Issue.record("Missing resume preparation")
		return
	}
	#expect(!resumedSession.isNew)
	_ = try await manager.start(
		.init(
			sessionID: sessionID, agentID: "chat", projectPath: prepared.projectPath,
			sessionFilePath: prepared.sessionFilePath, title: nil, firstRequest: false))
	#expect(runtime.startCount == 2)
}

@MainActor @Test func createStartsWithThePreparedProjectAndFirstRequestIntent() async throws {
	let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
	defer { try? FileManager.default.removeItem(at: root) }
	let preparations = SessionPreparationRegistry()
	let workspace = WorkspaceDataManager(projectsRoot: root, preparations: preparations)
	let runtime = ManagedRuntimeFixture()
	let manager = AgentProcessManager(projectsRoot: root, preparations: preparations) { _ in runtime }
	guard
		case .prepared(let prepared) = try await workspace.handle(
			.prepareCreateProject(request: "Build an app"))
	else {
		Issue.record("Missing Create preparation")
		return
	}
	let sessionID = URL(fileURLWithPath: prepared.sessionFilePath).deletingPathExtension()
		.lastPathComponent
	let request = try AgentSessionStartRequest(
		sessionID: sessionID, agentID: "create", projectPath: prepared.projectPath,
		sessionFilePath: prepared.sessionFilePath, title: prepared.title, firstRequest: true)
	await #expect(throws: AgentProcessManagerError.invalidScope) {
		_ = try await manager.start(
			.init(
				sessionID: sessionID, agentID: "create", projectPath: prepared.projectPath,
				sessionFilePath: prepared.sessionFilePath, title: prepared.title, firstRequest: false))
	}
	await #expect(throws: AgentProcessManagerError.invalidScope) {
		_ = try await manager.start(
			.init(
				sessionID: sessionID, agentID: "create", projectPath: prepared.projectPath,
				sessionFilePath: prepared.sessionFilePath, title: "Changed", firstRequest: true))
	}
	_ = try await manager.start(request)
	#expect(runtime.startCount == 1)
}

@MainActor @Test func failedStartRetainsServicePreparationForRetry() async throws {
	let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
	defer { try? FileManager.default.removeItem(at: root) }
	let project = root.appendingPathComponent(".chat")
	let session = project.appendingPathComponent(".pi/sessions/\(UUID().uuidString).jsonl")
	try FileManager.default.createDirectory(
		at: session.deletingLastPathComponent(), withIntermediateDirectories: true)
	let request = try AgentSessionStartRequest(
		sessionID: session.deletingPathExtension().lastPathComponent, agentID: "chat",
		projectPath: project.path, sessionFilePath: session.path, title: "Talk", firstRequest: false)
	let preparations = SessionPreparationRegistry()
	try issue(request, to: preparations)
	let runtime = ManagedRuntimeFixture()
	var failOnce = true
	let manager = AgentProcessManager(projectsRoot: root, preparations: preparations) { _ in
		if failOnce { failOnce = false; throw PiRPCError.unavailable }
		return runtime
	}
	await #expect(throws: PiRPCError.unavailable) { _ = try await manager.start(request) }
	_ = try await manager.start(request)
	#expect(runtime.startCount == 1)
}

@MainActor @Test func managerBindsChatAndCreateToTheirOwnProjectKinds() async throws {
	let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
	defer { try? FileManager.default.removeItem(at: root) }
	let chat = root.appendingPathComponent(".chat")
	let create = root.appendingPathComponent(UUID().uuidString.lowercased())
	let wrongName = root.appendingPathComponent("not-a-project-id")
	let missing = root.appendingPathComponent(UUID().uuidString.lowercased())
	let linked = root.appendingPathComponent(UUID().uuidString.lowercased())
	for project in [chat, create, wrongName] {
		try FileManager.default.createDirectory(
			at: project.appendingPathComponent(".pi/sessions"), withIntermediateDirectories: true)
	}
	try FileManager.default.createSymbolicLink(at: linked, withDestinationURL: wrongName)
	let runtime = ManagedRuntimeFixture()
	let preparations = SessionPreparationRegistry()
	let manager = AgentProcessManager(projectsRoot: root, preparations: preparations) { _ in runtime }
	func request(agent: String, project: URL, sessionID: String) throws -> AgentSessionStartRequest {
		try .init(
			sessionID: sessionID, agentID: agent, projectPath: project.path,
			sessionFilePath: project.appendingPathComponent(".pi/sessions/\(sessionID).jsonl").path,
			title: nil, firstRequest: false)
	}
	for (agent, project) in [
		("chat", create), ("create", chat), ("create", wrongName),
		("create", missing), ("create", linked), ("other", create),
	] {
		await #expect(throws: AgentProcessManagerError.invalidScope) {
			_ = try await manager.start(
				request(agent: agent, project: project, sessionID: UUID().uuidString))
		}
	}
	#expect(runtime.startCount == 0)
	let chatID = UUID().uuidString
	let createID = UUID().uuidString
	let chatRequest = try request(agent: "chat", project: chat, sessionID: chatID)
	let createRequest = try request(agent: "create", project: create, sessionID: createID)
	try issue(chatRequest, to: preparations)
	try issue(createRequest, to: preparations)
	_ = try await manager.start(chatRequest)
	_ = try await manager.start(createRequest)
	#expect(runtime.startCount == 2)
	_ = try await manager.stop(sessionID: chatID)
	_ = try await manager.stop(sessionID: createID)
}

@MainActor @Test func managerRejectsProjectsOutsideItsOwnedRoot() async throws {
	let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
	let runtime = ManagedRuntimeFixture()
	let manager = AgentProcessManager(
		projectsRoot: root, preparations: SessionPreparationRegistry()
	) { _ in runtime }
	let request = try AgentSessionStartRequest(
		sessionID: "session-1", agentID: "create", projectPath: "/tmp/outside",
		sessionFilePath: "/tmp/outside/.pi/sessions/session-1.jsonl", title: nil,
		firstRequest: false)
	await #expect(throws: AgentProcessManagerError.invalidScope) {
		try await manager.start(request)
	}
}
