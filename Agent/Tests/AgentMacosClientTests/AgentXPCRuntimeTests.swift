// @frontmatter:start
// Tests remote session startup, replay, reconnect, attach, prompt, and stop behavior.
// @frontmatter:end
import Foundation
import Testing

@testable import AgentMacosClient
import AgentMacosClientModel

private typealias PiRPCEvent = AgentMacosClientModel.PiRPCEvent

private typealias AgentSessionStartRequest = AgentMacosClientModel.AgentSessionStartRequest
private typealias AgentSessionPromptRequest = AgentMacosClientModel.AgentSessionPromptRequest
private typealias AgentSessionPollRequest = AgentMacosClientModel.AgentSessionPollRequest
private typealias AgentSessionEventBatch = AgentMacosClientModel.AgentSessionEventBatch
private typealias SequencedAgentServiceEvent = AgentMacosClientModel.SequencedAgentServiceEvent
private typealias AgentServiceEvent = AgentMacosClientModel.AgentServiceEvent

private actor SessionTransportFixture: AgentSessionTransport {
	var starts: [AgentSessionStartRequest] = []
	var prompts: [AgentSessionPromptRequest] = []
	var stopped: [String] = []
	var projectPaths: [String] = []
	var batches: [AgentSessionEventBatch]

	init(batches: [AgentSessionEventBatch]) { self.batches = batches }
	func startSession(_ request: AgentSessionStartRequest) async throws -> Int {
		starts.append(request)
		return 0
	}
	func prompt(_ request: AgentSessionPromptRequest, projectPath: String) async throws {
		prompts.append(request)
		projectPaths.append(projectPath)
	}
	func history(_ request: AgentSessionPollRequest, projectPath: String) async throws
		-> AgentSessionEventBatch
	{
		projectPaths.append(projectPath)
		return batches.removeFirst()
	}
	func subscribe(sessionID: String, projectPath: String) async throws
		-> (Int, AsyncThrowingStream<SequencedAgentServiceEvent, any Error>)
	{
		projectPaths.append(projectPath)
		let boundary = batches.reduce(0) { max($0, $1.nextCursor) }
		return (boundary, AsyncThrowingStream { $0.finish() })
	}
	func abort(sessionID: String, projectPath: String) async throws {}
	func stop(sessionID: String, projectPath: String) async throws -> Bool {
		projectPaths.append(projectPath)
		stopped.append(sessionID); return true
	}
}

@MainActor @Test func remoteRuntimeCannotChooseAnUnpreparedSessionPath() async throws {
	let transport = SessionTransportFixture(batches: [])
	let runtime = AgentXPCRuntime(transport: transport)
	await #expect(throws: AgentMacosClientModel.PiRPCError.unavailable) {
		_ = try await runtime.start(in: URL(fileURLWithPath: "/tmp/projects/project"))
	}
	#expect(await transport.starts.isEmpty)
}

@MainActor @Test func remoteRuntimeStartsSelectedAgentAndReplaysPushedHistory() async throws {
	let batch = AgentSessionEventBatch(
		events: [
			.init(sequence: 0, event: .textDelta("Remote")),
			.init(sequence: 1, event: .settled),
		],
		nextCursor: 2,
		terminal: true,
		failure: nil)
	let transport = SessionTransportFixture(batches: [batch])
	let runtime = AgentXPCRuntime(transport: transport)
	let project = URL(fileURLWithPath: "/tmp/projects/project")
	let session = project.appendingPathComponent(".pi/sessions/session-1.jsonl")
	let stream = try await runtime.start(
		agentID: "create", in: project, sessionFile: session, title: "Build", firstRequest: true)
	var received: [PiRPCEvent] = []
	for try await event in stream { received.append(event) }

	#expect(received == [.textDelta("Remote"), .settled])
	let starts = await transport.starts
	#expect(starts.first?.agentID == "create")
	#expect(starts.first?.sessionID == "session-1")
}

@MainActor @Test func remoteRuntimeRejectsUnknownTaskStatuses() async throws {
	let task = try AgentTaskRecord(id: "design", title: "Design", status: "unknown")
	let batch = AgentSessionEventBatch(
		events: [.init(sequence: 0, event: .tasksUpdated([task]))],
		nextCursor: 1, terminal: false, failure: nil)
	let runtime = AgentXPCRuntime(transport: SessionTransportFixture(batches: [batch]))
	let project = URL(fileURLWithPath: "/tmp/projects/project")
	let session = project.appendingPathComponent(".pi/sessions/session-1.jsonl")
	let stream = try await runtime.start(
		agentID: "create", in: project, sessionFile: session, title: nil, firstRequest: false)
	await #expect(throws: AgentMacosClientModel.PiRPCError.invalidRecord) {
		for try await _ in stream {}
	}
}

@MainActor @Test func remoteRuntimeAttachesWithoutStartingPi() async throws {
	let transport = SessionTransportFixture(batches: [])
	let runtime = AgentXPCRuntime(transport: transport)
	let file = URL(fileURLWithPath: "/tmp/projects/project/.pi/sessions/session-1.jsonl")
	let stream = try #require(try await runtime.attach(sessionFile: file))
	for try await _ in stream {}
	#expect(await transport.starts.isEmpty)
	#expect(await transport.projectPaths == ["/tmp/projects/project"])
	#expect(await runtime.detach())
	#expect(await transport.stopped.isEmpty)
}

@MainActor @Test func remoteRuntimeDoesNotDuplicateLoadedConversationOnReconnect() async throws {
	let transport = SessionTransportFixture(batches: [
		.init(
			events: [.init(sequence: 0, event: .textDelta("old answer"))],
			nextCursor: 1, terminal: false, failure: nil)
	])
	let runtime = AgentXPCRuntime(transport: transport)
	let project = URL(fileURLWithPath: "/tmp/projects/project")
	let session = project.appendingPathComponent(".pi/sessions/session-1.jsonl")
	let stream = try await runtime.start(
		agentID: "chat", in: project,
		sessionFile: session, title: nil, firstRequest: false, replayHistory: false)
	var seen: [PiRPCEvent] = []
	for try await event in stream { seen.append(event) }
	#expect(seen.isEmpty)
}

@MainActor @Test func remoteRuntimeRoutesPromptAndStopToActiveServiceSession() async throws {
	let transport = SessionTransportFixture(batches: [])
	let runtime = AgentXPCRuntime(transport: transport)
	let project = URL(fileURLWithPath: "/tmp/projects/project")
	let session = project.appendingPathComponent(".pi/sessions/session-2.jsonl")
	_ = try await runtime.start(
		agentID: "chat", in: project, sessionFile: session, title: nil, firstRequest: false)
	try await runtime.prompt("Continue")
	#expect(await runtime.stop())
	#expect(await transport.prompts.map(\.message) == ["Continue"])
	#expect(await transport.stopped == ["session-2"])
	#expect(await transport.projectPaths == Array(repeating: project.path, count: 3))
}
