// @frontmatter:start
// Owns Create's shared execution budget and confirms all constructed case cleanups once per collection.
// @frontmatter:end
import Foundation
import Scenario

@MainActor final class CreateCollection: CollectionContext {
	var contexts: [CreateCaseContext] = []
	private var emitted = false

	static func confirmationChain(
		emit: @escaping () -> Void = { print(CreateScenarioIsolation.confirmation) }
	) -> CleanupChain<CreateCollection> {
		CleanupChain(
			"confirm every constructed Create case",
			eligibility: { _, state in
				guard
					state.report.cleanupProblems.isEmpty
				else { throw ScenarioFailure.message("Observed cleanup failure; retain Create host") }
				return .run
			}, steps: [Step("emit collection cleanup confirmation") { try $0.confirmCleanup(emit: emit) }]
		)
	}

	func confirmCleanup(emit: () -> Void = { print(CreateScenarioIsolation.confirmation) }) throws {
		guard
			!contexts.isEmpty,
			contexts.allSatisfy(\.cleanupConfirmed)
		else {
			throw ScenarioFailure.message("Create collection cleanup unconfirmed; retain host/evidence")
		}
		if !emitted { emitted = true; emit() }
	}
}

@MainActor class CreateCaseContext: CaseContext {
	var runPassed = false
	var budget: Duration = .seconds(1020)
	private(set) var deadline: ContinuousClock.Instant?
	private(set) var cleanupConfirmed = false
	init() {}

	func startBudget() {
		if deadline == nil { deadline = ContinuousClock.now.advanced(by: budget) }
	}

	// Concrete cases own partial acquisition and fail closed when release cannot be proven.
	func cleanupResources() async throws {}

	final func cleanup() async throws {
		cleanupConfirmed = false
		try await cleanupResources()
		cleanupConfirmed = true
	}

	func withinBudget(_ execute: @escaping @MainActor () async throws -> Void) async throws {
		guard
			let deadline,
			ContinuousClock.now < deadline
		else { throw ScenarioFailure.message("Create execution deadline exceeded") }
		// Structured task-group exit awaits the cancelled loser before cleanup can start.
		try await withThrowingTaskGroup(of: Void.self) { group in
			group.addTask { try await execute() }
			group.addTask {
				try await ContinuousClock().sleep(until: deadline)
				throw ScenarioFailure.message("Create execution deadline exceeded")
			}
			defer { group.cancelAll() }
			try await group.next()
		}
	}
}

@MainActor enum CreateCases {
	static func step<Context: CreateCaseContext>(
		_ name: String, execute: @escaping @MainActor (Context) async throws -> Void
	) -> Step<Context> {
		Step(name) { context in try await context.withinBudget { try await execute(context) } }
	}

	static func makeCase<Context: CreateCaseContext>(
		_ name: String, context: @escaping @MainActor () -> Context,
		setup: [Step<Context>], behaviour: [Step<Context>]
	) -> ScenarioCase<CreateCollection> {
		ScenarioCase(
			name,
			context: { collection in
				let local = context()
				collection.contexts.append(local)
				return local
			}, setup: [Step("start absolute Create case budget") { $0.startBudget() }] + setup,
			behaviour: behaviour,
			cleanup: [
				CleanupChain(
					"release owned Create resources",
					eligibility: { local, state in
						let failed = state.report.steps.contains {
							$0.identity.caseName == name && $0.identity.phase != .cleanup && !$0.problems.isEmpty
						}
						// Retention must use the observed outcome, not an optimistic flag set within a phase.
						if failed || state.report.cancelled { local.runPassed = false }
						return .run
					},
					steps: [
						Step("await case resource cleanup") { try await $0.cleanup() }
					])
			])
	}
}
