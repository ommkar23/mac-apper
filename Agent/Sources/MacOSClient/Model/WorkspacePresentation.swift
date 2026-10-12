// @frontmatter:start
// Owns workspace UI actions, sheets, navigation, refresh, and host integration state.
// @frontmatter:end
import Foundation
import Observation

public enum WorkspaceSheet: Identifiable {
	case activity
	case rename(BuiltApp)
	public var id: String {
		switch self {
		case .activity: return "activity"
		case .rename(let app): return "rename:" + app.bundleURL.path
		}
	}
}

@MainActor public protocol WorkspaceHostActions {
	func launchApplication(at url: URL) async throws
	func openCodebaseInZed(at url: URL) async throws
	func copyDiagnostics(_ text: String) throws
	func revealLogs(at url: URL) throws
}

@MainActor @Observable public final class WorkspacePresentation {
	public let session: WorkspaceSession
	public var sheet: WorkspaceSheet?
	public private(set) var collapsedGroups: Set<URL> = []
	private var expandedPlan = false
	public var planExpanded: Bool {
		get { session.hasOngoingPlan && expandedPlan }
		set { expandedPlan = session.hasOngoingPlan && newValue }
	}
	public var renameDraft = ""
	public private(set) var renameError = ""
	public private(set) var launchError = ""
	private let host: (any WorkspaceHostActions)?
	private var launchGeneration = UUID()
	public private(set) var refreshing = false
	public private(set) var renameSubmitting = false
	public init(session: WorkspaceSession, host: (any WorkspaceHostActions)? = nil) {
		self.session = session
		self.host = host
	}

	public func refresh() async {
		if !session.switching { await session.refreshLibrary() }
		if !session.busy && !session.switching { await session.refreshSessions() }
		if !session.hasOngoingPlan { expandedPlan = false }
	}
	public func runRefreshLoop(interval: Duration = .seconds(1)) async {
		guard
			!refreshing
		else { return }
		refreshing = true
		defer { refreshing = false }
		while !Task.isCancelled {
			await refresh()
			do { try await Task.sleep(for: interval) } catch { return }
		}
	}
	private func resetNavigation() {
		launchGeneration = UUID()
		sheet = nil
		launchError = ""
		expandedPlan = false
	}
	public func newChat(newApp: Bool = false) async {
		guard
			session.canNavigate,
			!renameSubmitting
		else { return }
		resetNavigation()
		await session.newChat(newApp: newApp)
	}
	public func openSession(_ file: URL, in project: URL) async {
		guard
			session.canNavigate,
			!renameSubmitting
		else { return }
		resetNavigation()
		await session.openSession(file, in: project)
	}
	public func beginRename(_ app: BuiltApp) {
		guard
			session.canNavigate,
			!renameSubmitting
		else { return }
		renameDraft = app.name
		renameError = ""
		sheet = .rename(app)
	}
	public func cancelRename() { if !renameSubmitting && !session.renaming { sheet = nil } }
	public func confirmRename() async {
		guard
			canRename,
			case .rename(let app) = sheet
		else { return }
		renameSubmitting = true
		defer { renameSubmitting = false }
		renameError = ""
		let project =
			session.project?.lastPathComponent == app.projectName
			? session.project
			: session.library.first(where: { $0.project.lastPathComponent == app.projectName })?.project
		guard
			let project
		else {
			renameError = "Project is unavailable."
			return
		}
		if session.project?.standardizedFileURL != project.standardizedFileURL {
			await session.openProject(project)
		}
		guard
			session.project?.standardizedFileURL == project.standardizedFileURL
		else {
			renameError = session.activity
			return
		}
		if await session.renameApplication(to: renameDraft) {
			await session.refreshLibrary()
			sheet = nil
		} else {
			renameError = session.activity
		}
	}
	public func launchCurrentApp() async {
		guard
			canLaunch,
			let app = currentApp
		else { return }
		let ticket = UUID()
		launchGeneration = ticket
		let project = session.project
		launchError = ""
		do {
			guard
				let host
			else { throw PiRPCError.unavailable }
			try await host.launchApplication(at: app.bundleURL)
		} catch {
			guard
				launchGeneration == ticket,
				session.project == project
			else { return }
			launchError = "Couldn’t launch \(app.name): \(error.localizedDescription)"
		}
	}
	public func openCodebaseInZed() async {
		guard
			canOpenCodebase,
			let project = session.project
		else { return }
		launchError = ""
		do {
			guard
				let host
			else { throw PiRPCError.unavailable }
			try await host.openCodebaseInZed(at: project)
		} catch {
			guard
				session.project == project
			else { return }
			launchError = "Couldn’t open the codebase in Zed: \(error.localizedDescription)"
		}
	}
	public func copyDiagnostics() {
		do {
			guard
				let host
			else { throw PiRPCError.unavailable }
			try host.copyDiagnostics(session.safeDiagnostics)
		} catch { launchError = "Couldn’t copy diagnostics: \(error.localizedDescription)" }
	}
	public func revealLogs() async {
		await session.loadDiagnostics()
		guard
			let directory = session.diagnosticDirectory
		else { return }
		do {
			guard
				let host
			else { throw PiRPCError.unavailable }
			try host.revealLogs(at: directory)
		} catch { launchError = "Couldn’t reveal logs: \(error.localizedDescription)" }
	}

	public var selectedAgentID: String {
		get { session.selectedAgentID }
		set { session.selectAgent(newValue) }
	}
	public var selectedAgentName: String {
		session.agentPresets.first(where: { $0.id == session.selectedAgentID })?.displayName ?? "Agent"
	}
	public var diagnosticsPresented: Bool {
		if case .activity = sheet { return true }
		return false
	}
	public var currentApp: BuiltApp? {
		session.library.compactMap(\.app).first { $0.projectName == session.project?.lastPathComponent }
	}
	public var isInitialComposer: Bool { session.messages.isEmpty }
	public var canSendMessage: Bool {
		session.canSend && !session.idea.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
			&& session.idea.utf8.count <= 65_536
	}
	public var composerPlaceholder: String {
		if isInitialComposer {
			return session.isChatOnly
				? "What would you like to talk about?" : "What would you like to build?"
		}
		return session.busy ? "Send a message while Pi works…" : "Send a follow-up message…"
	}
	public var composerCaption: String {
		if session.isChatOnly { return "Chat only · local Pi" }
		if isInitialComposer { return "Swift · SwiftUI · local Pi" }
		return session.busy ? "Send to steer the current build" : "Continue this project"
	}
	public var composerAccessibilityLabel: String {
		isInitialComposer ? "Describe your request" : "Steering or follow-up message"
	}
	public var workspaceSubtitle: String {
		session.isChatOnly ? "Chat" : currentApp?.name ?? "App workspace"
	}
	public var emptyMessage: String {
		session.isChatOnly
			? "A conversation, without building an app." : "Create something native to your Mac."
	}
	public var footerText: String { launchError.isEmpty ? session.activity : launchError }
	public var canLaunch: Bool { !session.isChatOnly && currentApp != nil }
	public var canOpenCodebase: Bool { !session.isChatOnly && session.project != nil }
	public var canRename: Bool {
		!renameSubmitting && !session.renaming
			&& !renameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
	}
	public var renameButtonTitle: String { session.renaming ? "Renaming…" : "Rename" }
	public var scrollRevision: String {
		"\(session.messages.count):\(session.messages.last?.text ?? "")"
	}

	public func showDiagnostics() async { await session.loadDiagnostics(); sheet = .activity }
	public func dismissDiagnostics() { sheet = nil }
	public func toggleGroup(_ id: URL) {
		if !collapsedGroups.insert(id).inserted { collapsedGroups.remove(id) }
	}
	public func isSelected(_ file: URL) -> Bool {
		session.sessionFile?.standardizedFileURL.path == file.standardizedFileURL.path
	}
	public func openGroup(_ group: WorkspaceGroup) async {
		guard
			session.canNavigate,
			!renameSubmitting
		else { return }
		resetNavigation()
		if group.isChatOnly {
			await session.openBuiltInChat()
		} else {
			await session.openProject(group.project)
		}
	}
}
