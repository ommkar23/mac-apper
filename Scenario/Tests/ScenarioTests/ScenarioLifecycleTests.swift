import Foundation
import Testing
@testable import Scenario

@MainActor private final class LifecycleShared: CollectionContext {
	var events: [String] = []
	var started = false
	var cleanupStarted = false
}
@MainActor private final class LifecycleLocal: CaseContext {
	let shared: LifecycleShared
	var acquired = false
	init(_ shared: LifecycleShared) { self.shared = shared }
}

@Test @MainActor func namedLifecycleReportsAndCleanupDependencies() async throws {
	let shared = LifecycleShared()
	let registry = try ScenarioRegistry([
		ScenarioCollection(
			"named", context: { shared }, setup: [Step("shared setup") { $0.events.append("shared") }],
			cases: [
				ScenarioCase(
					"selected", context: LifecycleLocal.init,
					setup: [
						Step("acquire") {
							$0.acquired = true; $0.shared.events.append("acquired")
						}, Step("fail") { _ in throw ScenarioFailure.message("setup") },
					],
					behaviour: [Step("not run") { $0.shared.events.append("unexpected") }],
					cleanup: [
						CleanupChain(
							"owned", eligibility: { context, _ in context.acquired ? .run : .notAcquired },
							steps: [
								Step("reap") { _ in throw ScenarioFailure.message("cleanup") },
								Step("delete") { $0.shared.events.append("unsafe") },
							]),
						CleanupChain(
							"independent", steps: [Step("release") { $0.shared.events.append("released") }]),
						CleanupChain(
							"absent", eligibility: { _, _ in .notAcquired },
							steps: [Step("skip") { $0.shared.events.append("unexpected") }]),
					]),
				ScenarioCase(
					"unselected", context: LifecycleLocal.init,
					behaviour: [Step("unexpected") { $0.shared.events.append("unexpected") }]),
			], cleanup: [CleanupChain("shared", steps: [Step("finish") { $0.events.append("finished") }])]
		)
	])
	let report = try await registry.executeCase("selected")
	#expect(shared.events == ["shared", "acquired", "released", "finished"])
	#expect(report.bodyProblems.count == 1)
	#expect(report.cleanupProblems.count == 1)
	#expect(report.steps.contains { $0.skipReason == .priorSetupFailure })
	#expect(report.steps.contains { $0.skipReason == .cleanupPrerequisiteFailed })
	#expect(report.steps.contains { $0.skipReason == .resourceNotAcquired })
	#expect(!report.steps.contains { $0.identity.caseName == "unselected" })
	#expect(throws: ScenarioExecutionFailure.self) { try report.requireSuccess() }
}

@Test @MainActor func cancellationAwaitsUncancelledCleanupAndStopsCases() async throws {
	let shared = LifecycleShared()
	let registry = try ScenarioRegistry([
		ScenarioCollection(
			"cancel", context: { shared },
			cases: [
				ScenarioCase(
					"cancel-first", context: LifecycleLocal.init,
					behaviour: [Step("cancel") { _ in throw CancellationError() }],
					cleanup: [
						CleanupChain(
							"release",
							steps: [
								Step("await") { context in
									#expect(!Task.isCancelled)
									try await Task.sleep(for: .milliseconds(10))
									context.shared.events.append("awaited")
								}
							])
					]),
				ScenarioCase(
					"cancel-next", context: LifecycleLocal.init,
					behaviour: [Step("skip") { $0.shared.events.append("unexpected") }]),
			])
	])
	let report = try await registry.executeCollection("cancel")
	#expect(report.cancelled)
	#expect(shared.events == ["awaited"])
	#expect(
		report.steps.contains { $0.identity.caseName == "cancel-next" && $0.skipReason == .cancelled })
}

@Test @MainActor func failedFactoryReportsUnavailableCleanupAndContinues() async throws {
	let shared = LifecycleShared()
	let registry = try ScenarioRegistry([
		ScenarioCollection(
			"factory", context: { shared },
			cases: [
				ScenarioCase(
					"factory-fails",
					context: { _ throws -> LifecycleLocal in throw ScenarioFailure.message("factory") },
					behaviour: [], cleanup: [CleanupChain("unavailable", steps: [Step("skip") { _ in }])]),
				ScenarioCase(
					"factory-next", context: LifecycleLocal.init,
					behaviour: [Step("run") { $0.shared.events.append("next") }]),
			])
	])
	let report = try await registry.executeCollection("factory")
	#expect(shared.events == ["next"])
	#expect(report.steps.contains { $0.identity.phase == .context && $0.status == .failed })
	#expect(report.steps.contains { $0.skipReason == .contextUnavailable })
	#expect(report.steps.contains { $0.identity.step == "run" && $0.status == .completed })
}
