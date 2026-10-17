// @frontmatter:start
// Inspects the three real Create declarations and shared host boundaries without acquiring resources.
// @frontmatter:end
import Foundation
import Scenario
import Testing

@Suite @MainActor struct CreateContractTests {
	private var directory: URL { URL(fileURLWithPath: #filePath).deletingLastPathComponent() }
	private func declarations(_ collection: ScenarioCollection) throws -> [String] {
		try #require(
			Mirror(reflecting: collection).children.first { $0.label == "declarations" }?.value
				as? [String])
	}

	@Test func actualThreeCollectionsAreLightweightAndSelectExactlyOneCase() throws {
		for (collection, name) in [
			(createCounterCollection(requirePlan: false), "create-counter"),
			(createCounterCollection(requirePlan: true), "create-counter-plan"),
			(createHTViewCollection(), "create-htview"),
		] {
			let registry = try ScenarioRegistry([collection])
			#expect(registry.collectionNames == ["agent-create"])
			#expect(registry.caseNames == [name])
			let names = try declarations(collection)
			#expect(names.contains("start absolute Create case budget"))
			#expect(names.contains("release owned Create resources"))
			#expect(names.contains("await case resource cleanup"))
			#expect(names.contains("confirm every constructed Create case"))
			#expect(names.contains("emit collection cleanup confirmation"))
			#expect(names.count >= 18)
			#expect(names.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
		}
	}

	@Test func actualFactoriesExposeOrderedSetupBehaviourAndCleanupInventories() throws {
		let counter = [
			"validate private home and empty scoped library",
			"assign unchanged Pebble Counter prompt and optional plan request",
			"resolve and preflight explicit SDK compiler",
			"submit Create request and establish generation deadline",
			"await bounded settlement and capture permitted ownership",
			"audit completed Create presentation and case-specific session policy",
			"audit implementation-time plan and final tasks when requested",
			"audit latest authored passing counter Test before injection",
			"audit Preview archive and matched successful Build and Run",
			"audit canonical naming and absence of native rename notification",
			"refresh and audit canonical library title",
			"audit matched development bundle metadata",
			"capture exact development identity and verify private storage",
			"audit completed Test Preview Build Run activity", "review bounded generated sources",
			"compile and execute independent counter assertions",
			"verify development remains alive after independent verification",
			"verify production output remains absent",
			"review last validated Preview through integrated Vision", "mark counter behavior passed",
		]
		let htView = [
			"validate private home and empty library", "assign unchanged HTView prompt",
			"recheck staged credential lifetime", "preflight explicit SDK compiler",
			"submit HTView request",
			"await settlement and capture owned startup evidence",
			"audit completed Create profile and tools",
			"audit final-revision authored Test", "audit no Parallel and matched Build/Run",
			"capture development identity and audit private storage/activity",
			"independently verify generated WebKit document behavior", "verify development liveness",
			"report production output", "mark HTView behavior passed",
		]
		for (collection, phases) in [
			(createCounterCollection(requirePlan: false), counter),
			(createCounterCollection(requirePlan: true), counter), (createHTViewCollection(), htView),
		] {
			#expect(
				try declarations(collection) == [
					"confirm every constructed Create case", "emit collection cleanup confirmation",
					"start absolute Create case budget",
				] + phases + ["release owned Create resources", "await case resource cleanup"])
		}
	}

	@Test func unknownSelectionFailsBeforeAnyContextIsConstructed() async throws {
		let collection = CreateCollection()
		var constructed = false
		let registry = try ScenarioRegistry([
			ScenarioCollection(
				"create-selector", context: { collection }, setup: [],
				cases: [
					CreateCases.makeCase(
						"selected-create",
						context: {
							constructed = true; return CreateCaseContext()
						}, setup: [], behaviour: [])
				],
				cleanup: [CreateCollection.confirmationChain(emit: {})])
		])
		do {
			_ = try await registry.executeCase("unknown-create")
			Issue.record("Unknown Create selector was accepted")
		} catch {}
		#expect(!constructed && collection.contexts.isEmpty)
	}

	@Test func sharedBudgetAndHostDeadlinesAndProductionGatesRemain() throws {
		let inner = try String(
			contentsOf: directory.appendingPathComponent("CreateCaseLifecycle.swift"), encoding: .utf8)
		let outer = try String(
			contentsOf: directory.appendingPathComponent("CreateHostLifecycle.swift"), encoding: .utf8)
		#expect(CreateCaseContext().budget == .seconds(1020))
		#expect(inner.contains("final func cleanup() async throws"))
		#expect(outer.contains("timeoutSeconds: 1320"))
		#expect(outer.contains("home.finishHost("))
		#expect(outer.contains("includeDevTools: true, includeVision: vision, isolatedHome: home"))
		#expect(outer.contains("counterVisionEnvFile().path"))
		#expect(outer.contains("AGENT_CREATE_KEEP_PROJECT"))
		#expect(outer.contains("ScenarioTestingObserver()"))
		#expect(outer.components(separatedBy: "requireSuccess()").count == 3)
		#expect(!outer.contains("setenv("))
	}
}
