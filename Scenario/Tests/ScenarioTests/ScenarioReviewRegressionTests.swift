import Testing
import Scenario

@MainActor private final class ReviewShared: CollectionContext {
	var firstChainStarted = false
	var finishFirstChain = false
	var laterSnapshotCancelled = false
	var laterChainFinished = false
}
@MainActor private final class ReviewLocal: CaseContext {
	let shared: ReviewShared
	init(_ shared: ReviewShared) { self.shared = shared }
}

@Test @MainActor func cancellationDuringFirstCleanupReachesLaterEligibilitySnapshot() async throws {
	let shared = ReviewShared()
	let registry = try ScenarioRegistry([
		ScenarioCollection(
			"review-cancel", context: { shared },
			cases: [
				ScenarioCase(
					"review-cancel-case", context: ReviewLocal.init, behaviour: [],
					cleanup: [
						CleanupChain(
							"first",
							steps: [
								Step("wait for cancellation") { context in
									context.shared.firstChainStarted = true
									while !context.shared.finishFirstChain { await Task.yield() }
									#expect(!Task.isCancelled)
								}
							]),
						CleanupChain(
							"later",
							eligibility: { context, state in
								context.shared.laterSnapshotCancelled = state.report.cancelled
								#expect(!Task.isCancelled)
								return .run
							},
							steps: [
								Step("complete independently") { context in
									try await Task.sleep(for: .milliseconds(2))
									#expect(!Task.isCancelled)
									context.shared.laterChainFinished = true
								}
							]),
					])
			])
	])
	let task = Task { try await registry.executeCase("review-cancel-case") }
	while !shared.firstChainStarted { await Task.yield() }
	task.cancel()
	shared.finishFirstChain = true
	let report = try await task.value
	#expect(shared.laterSnapshotCancelled)
	#expect(shared.laterChainFinished)
	#expect(report.cancelled)
	#expect(report.cleanupProblems.isEmpty)
}

@Test @MainActor func thrownDiagnosticsRetainMultiCaseBodyAndCleanupIdentities() async throws {
	let registry = try ScenarioRegistry([
		ScenarioCollection(
			"review-diagnostics", context: ReviewShared.init,
			cases: [
				ScenarioCase(
					"review-first", context: ReviewLocal.init,
					behaviour: [Step("exercise first") { _ in throw ScenarioFailure.message("body one") }],
					cleanup: [
						CleanupChain(
							"first resources",
							steps: [Step("release first") { _ in throw ScenarioFailure.message("cleanup one") }])
					]),
				ScenarioCase(
					"review-second", context: ReviewLocal.init,
					steps: [Step("exercise second") { _ in throw ScenarioFailure.message("body two") }],
					teardown: { _ in throw ScenarioFailure.message("cleanup two") }),
			])
	])
	do {
		try await registry.runCollection("review-diagnostics")
		Issue.record("expected contextual execution failure")
	} catch let error as ScenarioExecutionFailure {
		let text = error.description
		#expect(
			text.contains("review-diagnostics / review-first / behaviour / exercise first: body one"))
		#expect(
			text.contains(
				"review-diagnostics / review-first / cleanup / first resources / release first: cleanup one"
			))
		#expect(
			text.contains("review-diagnostics / review-second / behaviour / exercise second: body two"))
		#expect(
			text.contains(
				"review-diagnostics / review-second / cleanup / case teardown / case teardown: cleanup two")
		)
		#expect(error.report.bodyProblems.count == 2)
		#expect(error.report.cleanupProblems.count == 2)
	}
}
