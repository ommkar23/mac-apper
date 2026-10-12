// @frontmatter:start
// Owns active Pi sessions, scoped lifecycle operations, event journaling, and subscriber handoff.
// @frontmatter:end
import Foundation

public enum AgentProcessManagerError: Error, Equatable {
	case invalidScope
	case duplicateSession
	case unknownSession
	case staleCursor
}

@MainActor public final class AgentProcessManager: AgentSessionManaging {
	public typealias RuntimeFactory = (AgentSessionStartRequest) throws -> any PiSessionRuntime

	private final class ManagedSession {
		let request: AgentSessionStartRequest
		let runtime: any PiSessionRuntime
		let journal: SessionEventJournal
		var nextSequence: Int
		var observers:
			[UUID: (
				event: (SequencedAgentServiceEvent) -> Void, finish: (String?) -> Void
			)] = [:]
		var baseCursor = 0
		var events: [SequencedAgentServiceEvent] = []
		var terminal = false
		var failure: String?
		var task: Task<Void, Never>?

		init(
			request: AgentSessionStartRequest, runtime: any PiSessionRuntime,
			journal: SessionEventJournal, nextSequence: Int
		) {
			self.request = request
			self.runtime = runtime
			self.journal = journal
			self.nextSequence = nextSequence
			self.baseCursor = nextSequence
		}
	}

	private let projectsRoot: URL
	private let eventLimit: Int
	private let runtimeFactory: RuntimeFactory
	private let preparations: SessionPreparationRegistry
	private var sessions: [String: ManagedSession] = [:]
	private var processActivity: NSObjectProtocol?

	public init(
		projectsRoot: URL,
		eventLimit: Int = 2_048,
		preparations: SessionPreparationRegistry,
		runtimeFactory: @escaping RuntimeFactory
	) {
		self.projectsRoot = projectsRoot.standardizedFileURL
		self.eventLimit = min(max(eventLimit, 1), 8_192)
		self.preparations = preparations
		self.runtimeFactory = runtimeFactory
	}

	public func start(_ request: AgentSessionStartRequest) async throws -> Int {
		if let existing = sessions[request.sessionID] {
			let active = existing.request
			guard
				active.agentID == request.agentID,
				active.projectPath == request.projectPath,
				active.sessionFilePath == request.sessionFilePath
			else { throw AgentProcessManagerError.duplicateSession }
			if !existing.terminal {
				preparations.discardIfMatches(request)
				return existing.nextSequence
			}
		}
		let (project, sessionFile) = try validate(request)
		try preparations.begin(request)
		var started = false
		defer { preparations.finish(sessionID: request.sessionID, started: started) }
		if sessions[request.sessionID]?.terminal == true {
			sessions.removeValue(forKey: request.sessionID)
		}
		let journal = try SessionEventJournal(sessionFile: sessionFile, sessionID: request.sessionID)
		let cursor = try journal.recover()
		let runtime = try runtimeFactory(request)
		let stream = try await runtime.start(
			agentID: request.agentID,
			in: project,
			sessionFile: sessionFile,
			title: request.title,
			firstRequest: request.firstRequest
		)
		let managed = ManagedSession(
			request: request, runtime: runtime,
			journal: journal, nextSequence: cursor)
		sessions[request.sessionID] = managed
		started = true
		retainProcessForActiveSessions()
		managed.task = Task { [weak self] in
			defer { managed.task = nil }
			do {
				for try await event in stream {
					guard
						let self
					else { return }
					try self.append(Self.wire(event), to: managed)
				}
				managed.terminal = true
				for observer in managed.observers.values { observer.finish(nil) }
				managed.observers.removeAll()
				self?.releaseProcessIfIdle()
			} catch {
				managed.failure = String(describing: error).prefix(500).description
				managed.terminal = true
				for observer in managed.observers.values { observer.finish(managed.failure) }
				managed.observers.removeAll()
				self?.releaseProcessIfIdle()
			}
		}
		return cursor
	}

	public func projectPath(sessionID: String) throws -> String {
		guard
			let managed = sessions[sessionID]
		else { throw AgentProcessManagerError.unknownSession }
		return managed.request.projectPath
	}

	public func prompt(_ request: AgentSessionPromptRequest) async throws {
		guard
			let managed = sessions[request.sessionID]
		else { throw AgentProcessManagerError.unknownSession }
		try await managed.runtime.prompt(request.message)
	}

	public func abort(sessionID: String) async throws {
		guard
			let managed = sessions[sessionID]
		else { throw AgentProcessManagerError.unknownSession }
		try await managed.runtime.abort()
	}

	@discardableResult public func stop(sessionID: String) async throws -> Bool {
		guard
			let managed = sessions[sessionID]
		else { throw AgentProcessManagerError.unknownSession }
		let stopped = await managed.runtime.stop()
		managed.terminal = true
		managed.task?.cancel()
		managed.task = nil
		for observer in managed.observers.values { observer.finish(nil) }
		managed.observers.removeAll()
		sessions.removeValue(forKey: sessionID)
		releaseProcessIfIdle()
		return stopped
	}

	public func history(sessionID: String, cursor: Int) throws -> AgentSessionEventBatch {
		guard
			let managed = sessions[sessionID]
		else { throw AgentProcessManagerError.unknownSession }
		let page = try managed.journal.page(cursor: cursor)
		return AgentSessionEventBatch(
			events: page.events, nextCursor: page.nextCursor,
			terminal: managed.terminal && page.nextCursor == managed.nextSequence,
			failure: managed.failure)
	}

	public func subscribe(
		sessionID: String, observer: @escaping (SequencedAgentServiceEvent) -> Void,
		onFinished: @escaping (String?) -> Void = { _ in }
	) throws -> (UUID, Int) {
		guard
			let managed = sessions[sessionID]
		else { throw AgentProcessManagerError.unknownSession }
		guard
			managed.observers.count < 32
		else { throw AgentProcessManagerError.invalidScope }
		let id = UUID()
		if managed.terminal {
			onFinished(managed.failure)
		} else {
			managed.observers[id] = (observer, onFinished)
		}
		return (id, managed.nextSequence)
	}

	public func unsubscribe(sessionID: String, id: UUID) {
		sessions[sessionID]?.observers.removeValue(forKey: id)
	}

	private func retainProcessForActiveSessions() {
		guard
			processActivity == nil
		else { return }
		processActivity = ProcessInfo.processInfo.beginActivity(
			options: [.userInitiated, .suddenTerminationDisabled, .automaticTerminationDisabled],
			reason: "Service-owned agent sessions are running")
	}

	private func releaseProcessIfIdle() {
		guard
			sessions.values.allSatisfy(\.terminal),
			let activity = processActivity
		else { return }
		ProcessInfo.processInfo.endActivity(activity)
		processActivity = nil
	}

	private func validate(_ request: AgentSessionStartRequest) throws -> (URL, URL) {
		guard
			!request.sessionID.isEmpty,
			request.sessionID.utf8.count <= 128,
			!request.agentID.isEmpty,
			request.agentID.utf8.count <= 128
		else { throw AgentProcessManagerError.invalidScope }
		let project = URL(fileURLWithPath: request.projectPath).standardizedFileURL
		let sessionFile = URL(fileURLWithPath: request.sessionFilePath).standardizedFileURL
		let projectKindMatches: Bool
		switch request.agentID {
		case "chat":
			projectKindMatches = project == WorkspaceLibrary.chatProject(in: projectsRoot)
		case "create":
			projectKindMatches = UUID(uuidString: project.lastPathComponent) != nil
		default: projectKindMatches = false
		}
		let projectValues = try? project.resourceValues(forKeys: [
			.isDirectoryKey, .isSymbolicLinkKey,
		])
		guard
			projectKindMatches,
			project.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL
				== projectsRoot.resolvingSymlinksInPath().standardizedFileURL,
			projectValues?.isDirectory == true,
			projectValues?.isSymbolicLink != true,
			sessionFile.deletingLastPathComponent().path
				== project.appendingPathComponent(".pi/sessions", isDirectory: true).standardizedFileURL
				.path,
			(try? ChatSessionCatalog.validate(sessionFile, in: project)) != nil
		else { throw AgentProcessManagerError.invalidScope }
		return (project, sessionFile)
	}

	private func append(_ event: AgentServiceEvent, to managed: ManagedSession) throws {
		let record = SequencedAgentServiceEvent(sequence: managed.nextSequence, event: event)
		try managed.journal.append(record)
		managed.nextSequence += 1
		managed.events.append(record)
		if managed.events.count > eventLimit {
			let overflow = managed.events.count - eventLimit
			managed.events.removeFirst(overflow)
			managed.baseCursor += overflow
		}
		for observer in managed.observers.values { observer.event(record) }
	}

	private static func wire(_ event: PiRPCEvent) -> AgentServiceEvent {
		switch event {
		case .response(let id, let command, let success, let error):
			return .response(id: id, command: command, success: success, error: error)
		case .textDelta(let text): return .textDelta(text)
		case .tasksUpdated(let tasks):
			return .tasksUpdated(
				tasks.map {
					AgentServiceTask(id: $0.id, title: $0.title, status: $0.status.rawValue)
				})
		case .toolStarted(let id, let name, let argumentsJSON):
			return .toolStarted(id: id, name: name, text: argumentsJSON)
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
