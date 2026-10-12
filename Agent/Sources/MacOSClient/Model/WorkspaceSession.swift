// @frontmatter:start
// Coordinates client session state, workspace navigation, Pi events, and project actions.
// @frontmatter:end
import Foundation
import Observation

@MainActor @Observable public final class WorkspaceSession {
	public var idea = ""
	public private(set) var state = AppModel()
	public private(set) var busy = false
	public private(set) var messages: [ChatMessage] = []
	public private(set) var connected = false
	public private(set) var switching = false
	public private(set) var renaming = false
	public private(set) var sessionFile: URL?
	public private(set) var sessions: [ChatSessionSummary] = []
	public private(set) var chatTitle = "New app"
	public private(set) var isChatOnly = false
	public private(set) var agentPresets: [AgentPresetSummary]
	public private(set) var selectedAgentID: String
	public var isNewAppPage: Bool { !isChatOnly && project == nil && messages.isEmpty }
	public var canNavigate: Bool { !busy && !switching && !renaming && !cleanupUnverified }
	public var canSend: Bool {
		!switching && !renaming && !cleanupUnverified && (!busy || connected)
			&& agentPresets.contains(where: { $0.id == selectedAgentID })
	}
	public var hasOngoingPlan: Bool { busy && !state.tasks.isEmpty }
	public private(set) var activity = "Ready to create a native macOS app with Pi."
	public private(set) var preview: URL?
	public private(set) var project: URL?
	public private(set) var safeDiagnostics =
		"Pi runs locally in RPC mode. Mac Apper does not use an HTTP service or container."
	public private(set) var diagnosticDirectory: URL?
	public var canSubmit: Bool { !busy && !cleanupUnverified }

	private let runtime: any AgentSessionRuntime
	private let workspaceStore: any WorkspaceStore
	private var work: Task<Void, Never>?
	private var generation = UUID()
	private var cleanupUnverified = false

	public init(
		runtime: any AgentSessionRuntime,
		workspaceStore: (any WorkspaceStore)? = nil
	) {
		self.runtime = runtime
		self.workspaceStore = workspaceStore ?? UnavailableWorkspaceStore()
		agentPresets = BuiltInAgentPresets.all
		selectedAgentID = "create"
	}

	private final class UnavailableWorkspaceStore: WorkspaceStore {
		func loadLibrary() async throws -> [WorkspaceGroup] { throw PiRPCError.unavailable }
		func loadProject(_ project: URL, session: URL?) async throws -> WorkspaceOpenResult {
			throw PiRPCError.unavailable
		}
		func loadSessions(in project: URL) async throws -> [ChatSessionSummary] {
			throw PiRPCError.unavailable
		}
		func loadChatProject() async throws -> WorkspaceOpenResult? { throw PiRPCError.unavailable }
		func prepareChatSession(request: String) async throws -> WorkspacePreparedSession {
			throw PiRPCError.unavailable
		}
		func prepareCreateProject(request: String) async throws -> WorkspacePreparedSession {
			throw PiRPCError.unavailable
		}
		func prepareCreateSession(in project: URL, request: String) async throws
			-> WorkspacePreparedSession
		{ throw PiRPCError.unavailable }
		func resumeSession(in project: URL, sessionFile: URL) async throws
			-> WorkspacePreparedSession
		{ throw PiRPCError.unavailable }
		func validatePreview(relativePath: String, project: URL) async throws -> URL? {
			throw PiRPCError.unavailable
		}
		func diagnosticDirectory(for project: URL) async throws -> URL {
			throw PiRPCError.unavailable
		}
	}

	public func selectAgent(_ id: String) {
		guard
			canNavigate,
			messages.isEmpty,
			project == nil,
			let preset = agentPresets.first(where: { $0.id == id })
		else { return }
		selectedAgentID = preset.id
		isChatOnly = preset.id == "chat"
		chatTitle = isChatOnly ? "New chat" : "New app"
	}

	public func loadDiagnostics() async {
		do {
			guard
				let project
			else {
				diagnosticDirectory = nil
				return
			}
			diagnosticDirectory = try await workspaceStore.diagnosticDirectory(for: project)
		} catch { diagnosticDirectory = nil; activity = "Could not load diagnostics: \(error)" }
	}

	public func refreshSessions() async {
		guard
			let project
		else {
			sessions = []
			return
		}
		do {
			sessions = try await workspaceStore.loadSessions(in: project)
		} catch {
			activity = "Could not read chat history: \(error)"
		}
	}

	public func newChat(newApp: Bool = false) async {
		guard
			canNavigate
		else { return }
		switching = true
		defer { switching = false }
		guard
			await leaveForNavigation()
		else { return }
		messages = []
		state = AppModel()
		idea = ""
		sessionFile = nil
		preview = nil
		if newApp {
			project = nil
			sessions = []
			selectedAgentID = "create"
			isChatOnly = false
		} else {
			await refreshSessions()
		}
		chatTitle = isChatOnly ? "New chat" : newApp || project == nil ? "New app" : "New chat"
		activity = "Send the first message to start."
	}

	public private(set) var library: [WorkspaceGroup] = []

	public func openBuiltInChat() async {
		guard
			canNavigate
		else { return }
		do {
			if let result = try await workspaceStore.loadChatProject() {
				await open(result)
			} else {
				await newChat(newApp: true)
				guard
					canNavigate
				else { return }
				isChatOnly = true
				selectedAgentID = agentPresets.first(where: { $0.id == "chat" })?.id ?? selectedAgentID
				chatTitle = "New chat"
			}
		} catch { activity = "Could not open chat: \(error)" }
	}

	public func refreshLibrary() async {
		do { library = try await workspaceStore.loadLibrary() } catch {
			activity = "Could not read app library: \(error)"
		}
	}

	public func openSession(_ file: URL, in target: URL) async {
		await openProject(target, session: file)
	}

	public func openProject(_ target: URL, session: URL? = nil) async {
		guard
			canNavigate
		else { return }
		switching = true
		defer { switching = false }
		do {
			let result = try await workspaceStore.loadProject(target, session: session)
			await open(result)
		} catch { activity = "Could not open app chat: \(error)" }
	}

	public func openChat(_ file: URL) async {
		guard
			canNavigate,
			let project
		else { return }
		switching = true
		defer { switching = false }
		do {
			let result = try await workspaceStore.loadProject(project, session: file)
			await open(result)
		} catch { activity = "Could not open chat: \(error)" }
	}

	private func open(_ result: WorkspaceOpenResult) async {
		guard
			await leaveForNavigation()
		else { return }
		project = result.project
		sessions = result.sessions
		isChatOnly = result.isChatOnly
		selectedAgentID =
			agentPresets.first(where: { $0.id == (result.isChatOnly ? "chat" : "create") })?.id
			?? selectedAgentID
		display(result.history)
		if let file = result.history?.summary.file,
			let events = try? await runtime.attach(sessionFile: file)
		{
			let ticket = UUID()
			generation = ticket
			connected = true
			work = Task { await observe(events, project: result.project, ticket: ticket) }
		}
	}

	private func leaveForNavigation() async -> Bool {
		guard
			connected || work != nil
		else { return true }
		generation = UUID()
		connected = false
		let detached = await runtime.detach()
		work?.cancel()
		if let work { await work.value }
		self.work = nil
		busy = false
		return detached
	}

	private func observe(
		_ events: AsyncThrowingStream<PiRPCEvent, any Error>,
		project: URL, ticket: UUID
	) async {
		do {
			for try await event in events {
				guard
					generation == ticket
				else { return }
				state.accept(event)
				switch event {
				case .textDelta(let text):
					busy = true
					if messages.last?.isUser == false {
						messages[messages.count - 1].text += text
					} else {
						messages.append(ChatMessage(isUser: false, text: text))
					}
				case .toolStarted(_, let name, _):
					busy = true
					activity = "Running \(name)…"
				case .toolFinished(_, let name, let text, let isError):
					activity = isError ? "\(name) failed: \(text.prefix(500))" : "\(name) completed."
					if name == "preview" || name == "run_with_config" {
						await discoverPreview(in: text, project: project)
					}
				case .settled:
					busy = false
					await refreshSessions()
					activity = state.status == "Failed" ? "Pi session failed." : "Pi session completed."
				case .extensionError(let message):
					activity = "Mac Apper extension failed: \(message.prefix(500))"
				default: break
				}
			}
			connected = false
			busy = false
		} catch {
			guard
				generation == ticket
			else { return }
			connected = false
			busy = false
			activity = "Pi session disconnected: \(String(describing: error).prefix(500))"
		}
	}

	private func display(_ history: ChatSessionHistory?) {
		state = AppModel()
		idea = ""
		preview = nil
		messages = history?.messages ?? []
		sessionFile = history?.summary.file
		chatTitle = history?.summary.title ?? "New chat"
		activity =
			history == nil
			? "Send the first message to start." : "Chat loaded. Send a message to continue."
	}

	public func submit() async {
		let request = idea.trimmingCharacters(in: .whitespacesAndNewlines)
		guard
			canSend,
			!request.isEmpty,
			request.utf8.count <= 65_536
		else { return }
		if connected {
			do {
				try await runtime.prompt(request)
				messages.append(ChatMessage(isUser: true, text: request))
				idea = ""
				busy = true
				activity = "Message sent to Pi…"
			} catch { activity = "Message could not be sent: \(error)" }
			return
		}
		busy = true
		messages.append(ChatMessage(isUser: true, text: request))
		idea = ""
		state = AppModel()
		preview = nil
		let ticket = UUID()
		generation = ticket
		let task = Task { await run(request: request, ticket: ticket) }
		work = task
		await withTaskCancellationHandler {
			await task.value
		} onCancel: {
			Task { @MainActor in _ = await self.cancel() }
		}
		if generation == ticket {
			work = nil
			busy = false
		}
	}

	@discardableResult public func renameApplication(to requestedName: String) async -> Bool {
		guard
			canNavigate,
			!isChatOnly,
			let project
		else { return false }
		let name: String
		let command: String
		do {
			name = try AppName.sanitize(requestedName)
			command = try AppName.renameCommand(for: name)
		} catch {
			activity = error.localizedDescription
			return false
		}

		renaming = true
		activity = "Rebuilding and renaming app to \(name)…"
		do {
			if connected {
				try await runtime.prompt(command)
				for _ in 0..<1_800 where renaming { try await Task.sleep(for: .milliseconds(100)) }
				guard
					!renaming
				else { throw PiRPCError.unavailable }
				return activity == "App renamed to \(name)."
			}

			let prepared = try await workspaceStore.prepareCreateSession(in: project, request: command)
			let events = try await runtime.start(
				agentID: "create", in: prepared.project, sessionFile: prepared.sessionFile,
				title: prepared.title, firstRequest: prepared.creatingApp, replayHistory: false)
			try await runtime.prompt(command)
			var succeeded = false
			for try await event in events {
				if consumeRename(event, expectedName: name) {
					succeeded = true
					break
				}
				if case .extensionError = event { break }
			}
			let stopped = await runtime.stop()
			if !stopped { cleanupUnverified = true }
			renaming = false
			if !succeeded && stopped { activity = "App rename failed." }
			return succeeded && stopped
		} catch {
			_ = await runtime.stop()
			renaming = false
			activity = "App rename failed: \(String(describing: error).prefix(500))"
			return false
		}
	}

	private func run(request: String, ticket: UUID) async {
		do {
			guard
				await runtime.stop()
			else { throw PiRPCError.unavailable }
			try Task.checkCancellation()
			let prepared: WorkspacePreparedSession
			if let sessionFile {
				guard
					let project,
					selectedAgentID == (project.lastPathComponent == ".chat" ? "chat" : "create")
				else { throw PiRPCError.unavailable }
				prepared = try await workspaceStore.resumeSession(
					in: project, sessionFile: sessionFile)
			} else if selectedAgentID == "chat" {
				guard
					project == nil || project?.lastPathComponent == ".chat"
				else { throw PiRPCError.unavailable }
				prepared = try await workspaceStore.prepareChatSession(request: request)
			} else if selectedAgentID == "create" {
				if let project {
					guard
						project.lastPathComponent != ".chat"
					else { throw PiRPCError.unavailable }
					prepared = try await workspaceStore.prepareCreateSession(in: project, request: request)
				} else {
					prepared = try await workspaceStore.prepareCreateProject(request: request)
				}
			} else {
				throw PiRPCError.unavailable
			}
			project = prepared.project
			sessionFile = prepared.sessionFile
			if prepared.isNew { chatTitle = prepared.title }
			activity = "Starting local Pi RPC session…"
			let events = try await runtime.start(
				agentID: selectedAgentID, in: prepared.project, sessionFile: prepared.sessionFile,
				title: prepared.isNew ? prepared.title : nil, firstRequest: prepared.creatingApp,
				replayHistory: prepared.isNew)
			try await runtime.prompt(request)
			connected = true
			activity = "Pi is working locally…"
			for try await event in events {
				guard
					generation == ticket
				else { return }
				try Task.checkCancellation()
				state.accept(event)
				switch event {
				case .textDelta(let text):
					if messages.last?.isUser == false {
						messages[messages.count - 1].text += text
					} else {
						messages.append(ChatMessage(isUser: false, text: text))
					}
				case .toolStarted(_, let name, _): activity = "Running \(name)…"
				case .toolFinished(_, let name, let text, let isError):
					activity = isError ? "\(name) failed: \(text.prefix(500))" : "\(name) completed."
					if name == "preview" || name == "run_with_config" {
						await discoverPreview(in: text, project: prepared.project)
					}
				case .extensionError(let message):
					activity = "Mac Apper extension failed: \(message.prefix(500))"
				case .notification(let message):
					if !consumeRename(event, expectedName: nil) { activity = message }
				case .settled:
					busy = false
					await refreshSessions()
					activity = state.status == "Failed" ? "Pi session failed." : "Pi session completed."
				default: break
				}
			}
			connected = false
			if state.status != "Completed" && state.status != "Failed" {
				throw PiRPCError.incompleteRecord
			}
		} catch {
			guard
				generation == ticket
			else { return }
			connected = false
			state.finish(cancelled: error is CancellationError)
			activity =
				error is CancellationError
				? "Cancelled. Project files preserved."
				: "Pi session stopped: \(String(describing: error).prefix(500))"
		}
	}

	private func discoverPreview(in text: String, project: URL) async {
		let marker = "MAC_APPER_PREVIEW:"
		guard
			let range = text.range(of: marker)
		else { return }
		let relative =
			text[range.upperBound...].split(whereSeparator: { $0 == "\n" || $0 == "\r" }).first.map(
				String.init) ?? ""
		do {
			preview = try await workspaceStore.validatePreview(relativePath: relative, project: project)
		} catch { preview = nil }
	}

	@discardableResult private func consumeRename(_ event: PiRPCEvent, expectedName: String?) -> Bool
	{
		guard
			case .notification(let message) = event,
			let name = AppName.decodeNotification(message),
			expectedName == nil || expectedName == name
		else { return false }
		renaming = false
		activity = "App renamed to \(name)."
		return true
	}

	@discardableResult public func cancel() async -> Bool {
		generation = UUID()
		connected = false
		work?.cancel()
		do { try await runtime.abort() } catch {}
		let stopped = await runtime.stop()
		if let work { await work.value }
		self.work = nil
		busy = false
		cleanupUnverified = !stopped
		state.finish(cancelled: true)
		preview = nil
		activity =
			stopped
			? "Cancelled. Project files preserved."
			: "Pi cleanup could not be verified. New work is disabled."
		return stopped
	}

	@discardableResult public func shutdown() async -> Bool {
		generation = UUID()
		connected = false
		let detached = await runtime.detach()
		work?.cancel()
		if let work { await work.value }
		self.work = nil
		busy = false
		return detached
	}
}
