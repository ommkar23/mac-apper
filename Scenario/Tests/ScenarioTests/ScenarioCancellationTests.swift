import Testing
@testable import Scenario

@MainActor private final class CancellationShared: CollectionContext {
	var bodyStarted = false
	var cleanupStarted = false
	var cleaned = false
	var events: [String] = []
}
@MainActor private final class CancellationLocal: CaseContext {
	let shared: CancellationShared
	init(_ shared: CancellationShared) { self.shared = shared }
}

@MainActor private func cancellationRegistry(_ shared: CancellationShared, suspendBody: Bool) throws
	-> ScenarioRegistry
{
	try ScenarioRegistry([
		ScenarioCollection(
			"cancellation", context: { shared },
			cases: [
				ScenarioCase(
					"cancellation-first", context: CancellationLocal.init,
					behaviour: [
						Step("body") { context in
							context.shared.bodyStarted = true
							if suspendBody {
								while !Task.isCancelled { await Task.yield() }
							}
						}
					],
					cleanup: [
						CleanupChain(
							"release",
							eligibility: { _, state in
								if suspendBody { #expect(state.report.cancelled) }
								return .run
							},
							steps: [
								Step("finish") { context in
									context.shared.cleanupStarted = true
									#expect(!Task.isCancelled)
									try await Task.sleep(for: .milliseconds(20))
									#expect(!Task.isCancelled)
									context.shared.cleaned = true
								}
							])
					]),
				ScenarioCase(
					"cancellation-later", context: CancellationLocal.init,
					behaviour: [Step("later") { $0.shared.events.append("unexpected") }]),
			])
	])
}

@Test @MainActor func actualCancellationAfterNormalBodyReturnIsReported() async throws {
	let shared = CancellationShared()
	let registry = try cancellationRegistry(shared, suspendBody: true)
	let task = Task { try await registry.executeCase("cancellation-first") }
	while !shared.bodyStarted { await Task.yield() }
	task.cancel()
	let report = try await task.value
	#expect(report.cancelled)
	#expect(shared.cleaned)
	#expect(throws: ScenarioExecutionFailure.self) { try report.requireSuccess() }
}

@Test @MainActor func cancellationDuringCleanupIsAwaitedAndStopsNextCase() async throws {
	let shared = CancellationShared()
	let registry = try cancellationRegistry(shared, suspendBody: false)
	let task = Task { try await registry.executeCollection("cancellation") }
	while !shared.cleanupStarted { await Task.yield() }
	task.cancel()
	let report = try await task.value
	#expect(shared.cleaned)
	#expect(shared.events.isEmpty)
	#expect(report.cancelled)
}

@Test @MainActor func cancellationBeforeAcquisitionSkipsFactories() async throws {
	let shared = CancellationShared()
	let registry = try cancellationRegistry(shared, suspendBody: false)
	let task = Task {
		withUnsafeCurrentTask { $0?.cancel() }
		return try await registry.executeCollection("cancellation")
	}
	let report = try await task.value
	#expect(report.cancelled)
	#expect(!shared.bodyStarted)
	#expect(!shared.cleaned)
	#expect(report.steps.allSatisfy { $0.status == .skipped })
}

@Test @MainActor func legacyUnnamedStepStillFailsAtExecutionNotRegistration() async throws {
	let shared = CancellationShared()
	let registry = try ScenarioRegistry([
		ScenarioCollection(
			"legacy", context: { shared },
			cases: [
				ScenarioCase(
					"legacy-case", context: CancellationLocal.init, steps: [Step("") { _ in }],
					teardown: { $0.shared.cleaned = true })
			])
	])
	await #expect(throws: (any Error).self) { try await registry.runCase("legacy-case") }
	#expect(shared.cleaned)
}
