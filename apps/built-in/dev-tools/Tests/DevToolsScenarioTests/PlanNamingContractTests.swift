// @frontmatter:start
// Checks Plan and naming declarative phase inventory without starting signed services.
// @frontmatter:end
import Foundation
import Testing

@Suite struct PlanNamingContractTests {
	@Test func actualDeclarationsUseNamedPhasesAndObservedExecution() throws {
		let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
		for (file, cases) in [("PlanTests.swift", 4), ("SetAppNameTests.swift", 2)] {
			let contents = try String(contentsOf: directory.appendingPathComponent(file), encoding: .utf8)
			let source = String(contents.components(separatedBy: "// Discovery-free regressions:")[0])
			#expect(!source.contains("setup: {"))
			#expect(!source.contains("teardown: {"))
			#expect(!source.contains("\n\t\t\t\tsteps: ["))
			#expect(source.components(separatedBy: "behaviour: [").count - 1 == cases)
			#expect(source.components(separatedBy: "cleanup: [").count - 1 == cases + 1)
			#expect(source.components(separatedBy: "try $0.lifecycle.teardown()").count - 1 == cases)
			#expect(
				source.components(
					separatedBy: "Step(\"confirm all assertions passed\") { $0.lifecycle.passed = true }"
				).count - 1 == cases)
			#expect(source.contains("ScenarioTestingObserver()"))
			#expect(source.contains("registry.executeCase(selected, observer: observer)"))
			#expect(source.contains("registry.executeCollection("))
			#expect(source.components(separatedBy: "try report.requireSuccess()").count - 1 == 2)
		}
	}

	@Test func meaningfulPlanAndNamingBoundariesRemainDeclared() throws {
		let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
		let expected: [String: [String]] = [
			"PlanTests.swift": [
				"prepare private home and signed generated-client host", "register primary project",
				"retrieve seeded plan", "retrieve added tasks", "retrieve remaining task",
				"create baseline plan", "seed baseline task", "verify unchanged task snapshot",
				"register secondary project", "reject missing secondary plan",
				"create empty secondary plan",
				"compare primary and secondary snapshots",
			],
			"SetAppNameTests.swift": [
				"prepare private signed host", "register primary project and capture baselines",
				"register foreign project", "preserve accepted non-ASCII control scalar",
				"preserve decomposed Unicode scalars",
			],
		]
		for (file, names) in expected {
			let source = try String(contentsOf: directory.appendingPathComponent(file), encoding: .utf8)
			for name in names { #expect(source.contains("Step(\"\(name)\")")) }
		}
	}
}
