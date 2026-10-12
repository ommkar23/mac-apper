// @frontmatter:start
// Adapts remote Agent sessions to the client runtime, replaying history before live events.
// @frontmatter:end
import Foundation

public protocol AgentSessionTransport: Sendable {
	func startSession(_ request: AgentSessionStartRequest) async throws -> Int
	func prompt(_ request: AgentSessionPromptRequest, projectPath: String) async throws
	func history(_ request: AgentSessionPollRequest, projectPath: String) async throws
		-> AgentSessionEventBatch
	func subscribe(sessionID: String, projectPath: String) async throws
		-> (Int, AsyncThrowingStream<SequencedAgentServiceEvent, any Error>)
	func abort(sessionID: String, projectPath: String) async throws
	func stop(sessionID: String, projectPath: String) async throws -> Bool
}

@MainActor public final class AgentXPCRuntime: AgentSessionRuntime {
	private let transport: any AgentSessionTransport
	private var activeSessionID: String?
	private var activeProjectPath: String?
	private var streamTask: Task<Void, Never>?

	public init(
		transport: any AgentSessionTransport
	) {
		self.transport = transport
	}

	public func sessionDirectory(in project: URL) -> URL {
		project.appendingPathComponent(".pi/sessions", isDirectory: true)
	}

	public func start(in project: URL) async throws -> AsyncThrowingStream<PiRPCEvent, any Error> {
		throw PiRPCError.unavailable
	}

	public func start(in project: URL, sessionFile: URL, title: String?) async throws
		-> AsyncThrowingStream<PiRPCEvent, any Error>
	{
		try await start(
			agentID: "create", in: project, sessionFile: sessionFile, title: title,
			firstRequest: false)
	}

	public func start(
		agentID: String, in project: URL, sessionFile: URL, title: String?, firstRequest: Bool
	) async throws -> AsyncThrowingStream<PiRPCEvent, any Error> {
		try await start(
			agentID: agentID, in: project, sessionFile: sessionFile, title: title,
			firstRequest: firstRequest, replayHistory: true)
	}

	public func start(
		agentID: String, in project: URL, sessionFile: URL, title: String?, firstRequest: Bool,
		replayHistory: Bool
	) async throws -> AsyncThrowingStream<PiRPCEvent, any Error> {
		guard
			activeSessionID == nil
		else { throw PiRPCError.rejected("a session is already attached") }
		let sessionID = sessionFile.deletingPathExtension().lastPathComponent
		let request = try AgentSessionStartRequest(
			sessionID: sessionID,
			agentID: agentID,
			projectPath: project.path,
			sessionFilePath: sessionFile.path,
			title: title,
			firstRequest: firstRequest)
		_ = try await transport.startSession(request)
		let (boundary, live) = try await transport.subscribe(
			sessionID: sessionID, projectPath: project.path)
		activeSessionID = sessionID
		activeProjectPath = project.path
		return makeEventStream(
			sessionID: sessionID, projectPath: project.path, boundary: boundary, live: live,
			replayHistory: replayHistory)
	}

	public func attach(sessionFile: URL) async throws
		-> AsyncThrowingStream<PiRPCEvent, any Error>?
	{
		guard
			activeSessionID == nil
		else { throw PiRPCError.rejected("a session is already attached") }
		let sessionID = sessionFile.deletingPathExtension().lastPathComponent
		let projectPath = sessionFile.deletingLastPathComponent()
			.deletingLastPathComponent().deletingLastPathComponent().path
		let (boundary, live) = try await transport.subscribe(
			sessionID: sessionID, projectPath: projectPath)
		activeSessionID = sessionID
		activeProjectPath = projectPath
		return makeEventStream(
			sessionID: sessionID, projectPath: projectPath, boundary: boundary, live: live,
			replayHistory: false)
	}

	private func makeEventStream(
		sessionID: String, projectPath: String, boundary: Int,
		live: AsyncThrowingStream<SequencedAgentServiceEvent, any Error>, replayHistory: Bool
	)
		-> AsyncThrowingStream<PiRPCEvent, any Error>
	{
		let transport = transport
		return AsyncThrowingStream { continuation in
			let task = Task {
				var cursor = replayHistory ? 0 : boundary
				do {
					while cursor < boundary {
						let batch = try await transport.history(
							.init(sessionID: sessionID, cursor: cursor), projectPath: projectPath)
						guard
							batch.nextCursor > cursor
						else { throw AgentServiceTransportError.invalidResponse }
						for item in batch.events where item.sequence < boundary {
							guard
								item.sequence == cursor
							else { throw AgentServiceTransportError.invalidResponse }
							continuation.yield(try Self.modelEvent(item.event))
							cursor += 1
						}
					}
					for try await item in live {
						if item.sequence < cursor { continue }
						guard
							item.sequence == cursor
						else { throw AgentServiceTransportError.invalidResponse }
						continuation.yield(try Self.modelEvent(item.event))
						cursor += 1
					}
					continuation.finish()
				} catch { continuation.finish(throwing: error) }
			}
			self.streamTask = task
			continuation.onTermination = { @Sendable _ in task.cancel() }
		}
	}

	public func prompt(_ message: String) async throws {
		guard
			let activeSessionID,
			let activeProjectPath
		else { throw PiRPCError.unavailable }
		try await transport.prompt(
			.init(sessionID: activeSessionID, message: message), projectPath: activeProjectPath)
	}

	public func abort() async throws {
		guard
			let activeSessionID,
			let activeProjectPath
		else { return }
		try await transport.abort(sessionID: activeSessionID, projectPath: activeProjectPath)
	}

	public func detach() async -> Bool {
		streamTask?.cancel()
		streamTask = nil
		activeSessionID = nil
		activeProjectPath = nil
		return true
	}

	public func stop() async -> Bool {
		guard
			let sessionID = activeSessionID,
			let projectPath = activeProjectPath
		else { return true }
		_ = await detach()
		do { return try await transport.stop(sessionID: sessionID, projectPath: projectPath) } catch {
			return false
		}
	}

	private static func modelEvent(_ event: AgentServiceEvent) throws -> PiRPCEvent {
		switch event {
		case .response(let id, let command, let success, let error):
			return .response(id: id, command: command, success: success, error: error)
		case .textDelta(let text): return .textDelta(text)
		case .tasksUpdated(let tasks):
			guard
				tasks.allSatisfy({ ["pending", "in_progress", "completed", "blocked"].contains($0.status) })
			else { throw PiRPCError.invalidRecord }
			return .tasksUpdated(tasks)
		case .toolStarted(let id, let name, let text):
			return .toolStarted(id: id, name: name, argumentsJSON: text)
		case .toolUpdated(let id, let name, let text):
			return .toolUpdated(id: id, name: name, text: text)
		case .toolFinished(let id, let name, let text, let isError):
			return .toolFinished(id: id, name: name, text: text, isError: isError)
		case .notification(let text): return .notification(text)
		case .extensionError(let text): return .extensionError(text)
		case .settled: return .settled
		}
	}
}
