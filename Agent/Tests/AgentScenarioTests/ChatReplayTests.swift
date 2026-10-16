// @frontmatter:start
// Declares detached Chat journal advancement, contiguous production replay and same-subscriber push with awaited owned cleanup.
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
	func close() async { task?.cancel(); await task?.value; task = nil }
}

@MainActor private final class ReplayContext: ChatCaseContext {
	let token = UUID().uuidString
	var session: ChatModelSession?
	var file: URL?
	var project: URL?
	var pid: String?
	var stamp: String?
	var detachedCursor: Int?
	var replay: ModelReplay?
	var countBeforePush: Int?
}

extension ChatModelCases {
	static func disconnectReplayCase() -> ScenarioCase<ChatCollection> {
		makeCase(
			"chat-disconnect-replay", context: ReplayContext.init,
			setup: [
				step("submit owned sequential-fetch replay request") { c in
					let token = c.token
					c.session = try await c.sessions.create(
						"Use Parallel MCP web_search through codemode to find current Japan news. Use web_fetch on three different result URLs sequentially. Read all three. Remember recall marker \(token). Then return only JSON with token and summary. No commentary or introduction."
					)
				}
			],
			behaviour: [
				step("await active work and capture original replay identity") { c in
					let session = try #require(c.session)
					try await session.waitUntilActive()
					c.file = try session.file
					c.project = try session.project
					let pid = try session.runningPi().pid
					c.pid = pid
					c.stamp = try session.processIdentity(pid)
					try #require(session.workspace.busy)
				},
				step("detach workspace without stopping Pi and capture cursor") { c in
					let session = try #require(c.session)
					try #require(await session.workspace.shutdown())
					#expect(!session.workspace.connected)
					c.detachedCursor = try await session.allHistory().count
				},
				step("await detached journal advancement within 120 seconds") { c in
					let session = try #require(c.session), detachedCursor = try #require(c.detachedCursor)
					let deadline = ContinuousClock.now.advanced(by: .seconds(120))
					while try await session.history(at: detachedCursor).nextCursor == detachedCursor {
						try Task.checkCancellation()
						guard
							ContinuousClock.now < deadline
						else {
							// Detachment must not stop service-owned journal delivery.
							throw ScenarioFailure.message("journal did not advance while the model was detached")
						}
						try await Task.sleep(for: .milliseconds(100))
					}
				},
				step("own production replay runtime and subscriber before waiting") { c in
					let project = try #require(c.project), file = try #require(c.file)
					let runtime = AgentXPCRuntime(transport: AgentServiceXPCAdapter())
					// Register before the first awaited acquisition, including partial startup failures.
					c.ownCleanup {
						let detached = await runtime.detach()
						#expect(detached)
						guard
							detached
						else { throw ScenarioFailure.message("Chat replay runtime detach unconfirmed") }
					}
					let stream = try await runtime.start(
						agentID: "chat", in: project, sessionFile: file,
						title: nil, firstRequest: false, replayHistory: true)
					let replay = ModelReplay(stream)
					c.ownCleanup { await replay.close() }
					c.replay = replay
				},
				step("await completed replay and verify original process continuity") { c in
					let session = try #require(c.session), replay = try #require(c.replay)
					let pid = try #require(c.pid), stamp = try #require(c.stamp)
					try await session.wait { !replay.failed && replay.state.status == "Completed" }
					#expect(try session.processIdentity(pid) == stamp)
				},
				step("compare first contiguous journal and replay transcript before reopening") { c in
					let session = try #require(c.session), replay = try #require(c.replay)
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
				},
				step("retain subscriber and reopen original workspace") { c in
					let session = try #require(c.session), replay = try #require(c.replay)
					let file = try #require(c.file), project = try #require(c.project)
					let pid = try #require(c.pid), stamp = try #require(c.stamp)
					c.countBeforePush = replay.events.count
					await session.workspace.openSession(file, in: project)
					try #require(session.workspace.connected)
					#expect(session.workspace.sessionFile == file)
					#expect(try session.processIdentity(pid) == stamp)
				},
				step("submit original recall question after first replay comparison") { c in
					let session = try #require(c.session)
					try await session.submit(
						"Return only JSON with country Japan and the token containing the recall marker I gave in my previous request. Do not repeat the news or use tools."
					)
				},
				step("verify recalled marker") { c in
					let session = try #require(c.session)
					try checkRecall(try await session.answer(), country: "Japan", token: c.token)
				},
				step("compare later push on the same subscriber with the complete journal") { c in
					let session = try #require(c.session), replay = try #require(c.replay)
					let countBeforePush = try #require(c.countBeforePush)
					let completeJournal = try await session.allHistory()
					try await session.wait(timeout: 10) {
						replay.failed || replay.events.count >= completeJournal.count
					}
					#expect(!replay.failed)
					#expect(replay.events.count > countBeforePush)
					#expect(completeJournal.map(\.sequence) == Array(0..<completeJournal.count))
					#expect(replay.events == completeJournal.map { modelEvent($0.event) })
				},
			])
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
