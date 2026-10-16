import Testing
@testable import Scenario

@MainActor private final class PhaseShared: CollectionContext {
	var events: [String] = []
}
@MainActor private final class PhaseLocal: CaseContext {
	let shared: PhaseShared
	init(_ shared: PhaseShared) { self.shared = shared }
}

@Test @MainActor func declarativePhaseOrderAndCleanupSnapshots() async throws {
	let shared = PhaseShared()
	let registry = try ScenarioRegistry([
		ScenarioCollection(
			"phases", context: { shared },
			setup: [Step("collection prepare") { $0.events.append("collection setup") }],
			cases: [
				ScenarioCase(
					"phase-case", context: PhaseLocal.init,
					setup: [Step("prepare") { $0.shared.events.append("setup") }],
					behaviour: [Step("exercise") { $0.shared.events.append("behaviour") }],
					cleanup: [
						CleanupChain("first", steps: [Step("release") { $0.shared.events.append("cleanup") }]),
						CleanupChain(
							"second",
							eligibility: { _, state in
								#expect(
									state.report.steps.contains {
										$0.identity.step == "release" && $0.status == .completed
									})
								return .run
							}, steps: []),
					])
			],
			cleanup: [
				CleanupChain(
					"collection",
					eligibility: { _, state in
						#expect(
							state.report.steps.contains {
								$0.identity.caseName == "phase-case" && $0.identity.phase == .cleanup
							})
						return .run
					}, steps: [Step("finish") { $0.events.append("collection cleanup") }])
			])
	])
	let report = try await registry.executeCollection("phases")
	try report.requireSuccess()
	#expect(
		shared.events == ["collection setup", "setup", "behaviour", "cleanup", "collection cleanup"])
	#expect(report.steps.allSatisfy { $0.elapsed >= .zero })
	#expect(report.steps.allSatisfy { !$0.assertionsObserved })
}

@Test @MainActor func failedCollectionSetupSkipsCasesButReleasesPartialOwnership() async throws {
	let shared = PhaseShared()
	let registry = try ScenarioRegistry([
		ScenarioCollection(
			"partial", context: { shared },
			setup: [
				Step("partial") { context in
					context.events.append("owned")
					throw ScenarioFailure.message("setup failure")
				}, Step("skipped") { $0.events.append("unexpected") },
			],
			cases: [
				ScenarioCase(
					"partial-case",
					context: { context in
						context.events.append("unexpected factory"); return PhaseLocal(context)
					}, behaviour: [Step("skipped") { $0.shared.events.append("unexpected") }],
					cleanup: [CleanupChain("unavailable", steps: [Step("skip") { _ in }])])
			],
			cleanup: [CleanupChain("release", steps: [Step("finish") { $0.events.append("released") }])])
	])
	let report = try await registry.executeCollection("partial")
	#expect(shared.events == ["owned", "released"])
	#expect(report.bodyProblems.count == 1)
	#expect(
		report.steps.contains {
			$0.identity.caseName == "partial-case" && $0.skipReason == .collectionSetupFailure
		})
}

@Test @MainActor func failedCollectionFactoryCannotRunCleanup() async throws {
	let registry = try ScenarioRegistry([
		ScenarioCollection(
			"no-context",
			context: { () throws -> PhaseShared in throw ScenarioFailure.message("no context") },
			setup: [], cases: [ScenarioCase("no-context-case", context: PhaseLocal.init, behaviour: [])],
			cleanup: [
				CleanupChain(
					"not available", steps: [Step("skip") { _ in Issue.record("unexpected cleanup") }])
			])
	])
	let report = try await registry.executeCollection("no-context")
	#expect(report.bodyProblems.count == 1)
	#expect(
		report.steps.contains { $0.identity.phase == .cleanup && $0.skipReason == .contextUnavailable })
}

@Test @MainActor func uncertainEligibilityFailsClosedAndIndependentChainContinues() async throws {
	let shared = PhaseShared()
	let registry = try ScenarioRegistry([
		ScenarioCollection(
			"eligibility", context: { shared },
			cases: [
				ScenarioCase(
					"eligibility-case", context: PhaseLocal.init, behaviour: [],
					cleanup: [
						CleanupChain(
							"uncertain",
							eligibility: { _, _ in throw ScenarioFailure.message("unknown ownership") },
							steps: [Step("delete") { $0.shared.events.append("unsafe") }]),
						CleanupChain(
							"independent", steps: [Step("release") { $0.shared.events.append("independent") }]),
					])
			])
	])
	let report = try await registry.executeCase("eligibility-case")
	#expect(shared.events == ["independent"])
	#expect(report.cleanupProblems.count == 1)
	#expect(report.cleanupProblems.first?.origin == .eligibility)
}

@Test @MainActor func newDeclarationValidationDoesNotConstructContexts() throws {
	let shared = PhaseShared()
	#expect(throws: (any Error).self) {
		_ = try ScenarioRegistry([
			ScenarioCollection(
				"validation",
				context: {
					shared.events.append("unexpected"); return shared
				},
				cases: [
					ScenarioCase(
						"validation-case", context: PhaseLocal.init, behaviour: [Step("  ") { _ in }])
				])
		])
	}
	#expect(shared.events.isEmpty)
}
