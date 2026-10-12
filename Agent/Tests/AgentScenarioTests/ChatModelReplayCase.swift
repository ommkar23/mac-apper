// @frontmatter:start
// Verifies client-model detachment, ordered history-plus-push replay, process continuity, and context recall through real Agent XPC.
// @frontmatter:end
import AgentMacosClient
import AgentMacosClientModel
import Foundation
import Scenario
import Testing

@MainActor private final class ModelReplay {
	let state = AppModel()
	var events: [PiRPCEvent] = []
	var failed = false
	private var task: Task<Void, Never>?
	init(_ stream: AsyncThrowingStream<PiRPCEvent, any Error>) {
		task = Task { [weak self] in
			do {
				for try await event in stream {
					guard
						let self
					else { return }
					guard
						events.count < 8192
					else {
						failed = true
						return
					}
					events.append(event); state.accept(event)
				}
			} catch { if !Task.isCancelled { self?.failed = true } }
		}
	}
	func cancel() { task?.cancel() }
	func close() async { task?.cancel(); await task?.value; task = nil }
}

extension ChatModelCases {
	static func disconnectReplay(_ sessions: ChatModelSessions) async throws {
		let token = UUID().uuidString
		let session = try await sessions.create(
			"Use Parallel MCP web_search through codemode to find current Japan news. Use web_fetch on three different result URLs sequentially. Read all three. Remember recall marker \(token). Then return only JSON with token and summary. No commentary or introduction."
		)
		try await session.waitUntilActive()
		let file = try session.file, project = try session.project
		let pid = try session.runningPi().pid, stamp = try session.processIdentity(pid)
		try #require(session.workspace.busy)
		try #require(await session.workspace.shutdown())
		#expect(!session.workspace.connected)
		let detachedCursor = try await session.allHistory().count
		let deadline = ContinuousClock.now.advanced(by: .seconds(120))
		while try await session.history(at: detachedCursor).nextCursor == detachedCursor {
			try Task.checkCancellation()
			guard
				ContinuousClock.now < deadline
			else { throw ScenarioFailure.message("journal did not advance while the model was detached") }
			try await Task.sleep(for: .milliseconds(100))
		}
		// Replay through the production client-owned runtime and its observable presentation model.
		let runtime = AgentXPCRuntime(transport: AgentServiceXPCAdapter())
		let stream = try await runtime.start(
			agentID: "chat", in: project, sessionFile: file,
			title: nil, firstRequest: false, replayHistory: true)
		let replay = ModelReplay(stream)
		defer { replay.cancel() }
		try await session.wait { !replay.failed && replay.state.status == "Completed" }
		#expect(try session.processIdentity(pid) == stamp)
		let firstJournal = try await session.allHistory()
		try await session.wait(timeout: 10) {
			replay.failed || replay.events.count >= firstJournal.count
		}
		try #require(!replay.failed)
		#expect(replay.events == firstJournal.map { modelEvent($0.event) })
		#expect(firstJournal.map(\.sequence) == Array(0..<firstJournal.count))
		#expect(
			replay.state.transcript
				== firstJournal.compactMap { event in
					if case .textDelta(let text) = event.event { return text }; return nil
				}.joined())
		#expect(
			["mcp__parallel__web_search", "mcp__parallel__web_fetch"].allSatisfy { name in
				replay.state.liveDetails.contains(where: { $0.hasPrefix("\(name) · completed") })
			})
		#expect(
			try session.successfulTools.isSuperset(of: [
				"codemode", "mcp__parallel__web_search", "mcp__parallel__web_fetch",
			]))
		let countBeforePush = replay.events.count
		await session.workspace.openSession(file, in: project)
		try #require(session.workspace.connected)
		#expect(session.workspace.sessionFile == file)
		#expect(try session.processIdentity(pid) == stamp)
		try checkRecall(
			try await session.prompt(
				"Return only JSON with country Japan and the token containing the recall marker I gave in my previous request. Do not repeat the news or use tools."
			), country: "Japan", token: token)
		let completeJournal = try await session.allHistory()
		try await session.wait(timeout: 10) {
			replay.failed || replay.events.count >= completeJournal.count
		}
		#expect(!replay.failed)
		#expect(replay.events.count > countBeforePush)
		#expect(completeJournal.map(\.sequence) == Array(0..<completeJournal.count))
		#expect(replay.events == completeJournal.map { modelEvent($0.event) })
		await replay.close()
		#expect(await runtime.detach())
	}

	private static func modelEvent(_ event: AgentServiceEvent) -> PiRPCEvent {
		switch event {
		case .response(let id, let command, let success, let error):
			return .response(id: id, command: command, success: success, error: error)
		case .textDelta(let text): return .textDelta(text)
		case .tasksUpdated(let tasks): return .tasksUpdated(tasks)
		case .toolStarted(let id, let name, let text):
			return .toolStarted(id: id, name: name, argumentsJSON: text)
		case .toolUpdated(let id, let name, let text):
			return .toolUpdated(id: id, name: name, text: text)
		case .toolFinished(let id, let name, let text, let error):
			return .toolFinished(id: id, name: name, text: text, isError: error)
		case .notification(let text): return .notification(text)
		case .extensionError(let text): return .extensionError(text)
		case .settled: return .settled
		}
	}
}
