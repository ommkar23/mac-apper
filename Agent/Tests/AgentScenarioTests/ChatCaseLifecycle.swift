// @frontmatter:start
// Owns Chat case deadlines, auxiliary release actions and collection-wide cleanup confirmation.
// @frontmatter:end
import Foundation
import Scenario
import Testing

@MainActor final class ChatCollection: CollectionContext {
	var contexts: [ChatCaseContext] = []
	static func confirmationChain(
		emit: @escaping () -> Void = { print(ChatScenarioCleanup.confirmation) }
	) -> CleanupChain<ChatCollection> {
		CleanupChain(
			"confirm every constructed Chat case",
			eligibility: { _, state in
				guard
					state.report.cleanupProblems.isEmpty
				else {
					// Observed nonthrowing cleanup issues cannot authorize host removal.
					throw ScenarioFailure.message("Observed Chat cleanup failure; retain host/evidence")
				}
				return .run
			}, steps: [Step("emit collection cleanup confirmation") { try $0.confirmCleanup(emit: emit) }]
		)
	}
	func confirmCleanup(emit: () -> Void = { print(ChatScenarioCleanup.confirmation) }) throws {
		guard
			!contexts.isEmpty,
			contexts.allSatisfy(\.cleanupConfirmed)
		else {
			throw ScenarioFailure.message("Chat collection cleanup unconfirmed; retain host/evidence")
		}
		emit()
	}
}

@MainActor class ChatCaseContext: CaseContext {
	let sessions = ChatModelSessions()
	var budget: Duration = .seconds(220)
	private(set) var deadline: ContinuousClock.Instant?
	private(set) var cleanupConfirmed = false
	private var actions: [@MainActor () async throws -> Void] = []
	// Offline lifecycle fixtures can replace session release without acquiring a client.
	var releaseSessions: (@MainActor () async throws -> Void)?
	init() {}

	func startBudget() { if deadline == nil { deadline = .now.advanced(by: budget) } }
	func ownCleanup(_ closure: @escaping @MainActor () async throws -> Void) {
		actions.append(closure)
	}
	func cleanup() async throws {
		cleanupConfirmed = false
		var failures: [String] = []
		for action in actions.reversed() {
			do { try await action() } catch { failures.append(String(describing: error)) }
		}
		do {
			if let releaseSessions {
				try await releaseSessions()
			} else {
				try await sessions.cleanup(emitConfirmation: false)
			}
		} catch { failures.append(String(describing: error)) }
		guard
			failures.isEmpty
		else {
			throw ScenarioFailure.message("Chat case cleanup failed; retain host/evidence: \(failures)")
		}
		cleanupConfirmed = true
	}

	func withinBudget(_ execute: @escaping @MainActor () async throws -> Void) async throws {
		guard
			let deadline,
			ContinuousClock.now < deadline
		else { throw ScenarioFailure.message("Chat execution deadline exceeded") }
		try await withThrowingTaskGroup(of: Void.self) { group in
			group.addTask { try await execute() }
			group.addTask {
				try await ContinuousClock().sleep(until: deadline)
				throw ScenarioFailure.message("Chat execution deadline exceeded")
			}
			defer { group.cancelAll() }
			try await group.next()
		}
	}
}

extension ChatModelCases {
	static func step<Context: ChatCaseContext>(
		_ name: String, execute: @escaping @MainActor (Context) async throws -> Void
	) -> Step<Context> {
		Step(name) { context in try await context.withinBudget { try await execute(context) } }
	}

	static func makeCase<Context: ChatCaseContext>(
		_ name: String, context: @escaping @MainActor () -> Context,
		setup: [Step<Context>], behaviour: [Step<Context>]
	) -> ScenarioCase<ChatCollection> {
		ScenarioCase(
			name,
			context: { collection in
				let local = context()
				collection.contexts.append(local)
				return local
			},
			setup: [Step("start absolute Chat case budget") { $0.startBudget() }] + setup,
			behaviour: behaviour + [
				step("audit completed Chat presentation") { local in
					for session in local.sessions.owned {
						let audit = try session.audit()
						#expect(audit.profile == .required)
						#expect(session.workspace.selectedAgentID == "chat")
						#expect(session.workspace.isChatOnly)
						#expect(session.workspace.state.status == "Completed")
					}
				}
			],
			cleanup: [
				CleanupChain(
					"release Chat resources",
					steps: [
						Step("close auxiliary resources then clean every owned session") {
							try await $0.cleanup()
						}
					])
			])
	}
}
