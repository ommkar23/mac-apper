// @frontmatter:start
// Checks Test and Build/Run declarative phases, observed failure gating, and synchronous handshake contracts offline.
// @frontmatter:end
import Foundation
import Scenario
import ScenarioTesting
@_spi(Experimental) import Testing

@Suite @MainActor struct TestToolchainContractTests {
	private func source(_ name: String) throws -> String {
		try String(
			contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent()
				.appendingPathComponent(name), encoding: .utf8)
	}

	@Test func entryPointsDeclareObservedPhases() throws {
		for name in ["TestTests.swift", "ToolchainTests.swift"] {
			let text = try source(name)
			#expect(text.contains("import ScenarioTesting"))
			#expect(text.contains("behaviour: ["))
			#expect(text.contains("cleanup: ["))
			#expect(text.contains("observer: ScenarioTestingObserver()"))
			#expect(text.contains("report.requireSuccess()"))
			#expect(text.contains("Step(\"mark successful completion\")"))
			#expect(!text.contains("registry.runCase(") && !text.contains("registry.runCollection("))
			#expect(!text.contains("teardown: {"))
			#expect(text.components(separatedBy: "lifecycle.passed = true").count == 2)
			#expect(
				text.range(
					of:
						#"Step\("mark successful completion"\) \{ \$0\.(collection\.)?lifecycle\.passed = true \}"#,
					options: .regularExpression) != nil)
		}
	}

	@Test func testSnapshotsStayPerRequestAndHandshakeBoundsStaySynchronous() throws {
		let test = try source("TestTests.swift")
		let check = try #require(test.range(of: "func check(status:"))
		let body = String(test[check.lowerBound...])
		#expect(body.contains("let manifest = try Data(contentsOf:"))
		#expect(body.contains("== manifest"))
		#expect(body.contains("== model"))
		#expect(body.contains("== tests"))
		let toolchain = try source("ToolchainTests.swift")
		#expect(toolchain.contains("systemUptime + 60"))
		#expect(toolchain.contains(".milliseconds(50)"))
		#expect(toolchain.contains("let deadline = operations.now() + 10"))
		#expect(toolchain.contains("try OwnedExecutableProcess.capture(executable: $0)"))
		#expect(!toolchain.contains("DEV_TOOLS_SCENARIO_CASE"))
		let start = try #require(toolchain.range(of: "func launchAcquireRelease() throws"))
		let end = try #require(toolchain.range(of: "func awaitNaturalExit()"))
		let synchronous = String(toolchain[start.lowerBound..<end.lowerBound])
		#expect(!synchronous.contains("await "))
		let attempted = try #require(synchronous.range(of: "lifecycle.childAttempted = true"))
		let run = try #require(synchronous.range(of: "request(\"run\""))
		#expect(attempted.lowerBound < run.lowerBound)
		let deadline = try #require(
			synchronous.range(of: "exitDeadline = ContinuousClock.now.advanced(by: .seconds(10))"))
		let acquire = try #require(synchronous.range(of: "ToolchainScenarioHandshake.acquire("))
		#expect(deadline.lowerBound < acquire.lowerBound)
	}

	@Test func actualInventoryIsAllocationFreeAndRejectsUnknownSelectors() async throws {
		var constructed = 0
		let registry = try ScenarioRegistry([
			devToolsTestCollection(context: {
				constructed += 1
				return DevToolsTestCollection()
			}),
			devToolsToolchainCollection(context: {
				constructed += 1
				return DevToolsToolchainCollection()
			}),
		])
		#expect(registry.collectionNames == ["dev-tools-test", "dev-tools-toolchain"])
		#expect(registry.caseNames == ["test-package", "toolchain-build-run"])
		#expect(constructed == 0)
		do {
			_ = try await registry.executeCase("unknown-case", observer: ScenarioTestingObserver())
			Issue.record("unknown case accepted")
		} catch ScenarioFailure.message(let diagnostic) {
			#expect(diagnostic == "unknown case: unknown-case")
		}
		#expect(constructed == 0)
		do {
			_ = try await registry.executeCollection(
				"unknown-collection", observer: ScenarioTestingObserver())
			Issue.record("unknown collection accepted")
		} catch ScenarioFailure.message(let diagnostic) {
			#expect(diagnostic == "unknown collection: unknown-collection")
		}
		#expect(constructed == 0)
	}

	@Test func actualTestCollectionCleansUpAfterCaseSetupFailure() async throws {
		let shared = DevToolsTestCollection()
		// No shared acquisition: the real project's registration fails before any writes.
		let registry = try ScenarioRegistry([devToolsTestCollection(context: { shared }, setup: [])])
		let test = try #require(Test.current)
		let outer = IssueHandlingTrait.compactMapIssues { issue in
			issue.comments.contains { $0.rawValue == "Test project registry unavailable" } ? nil : issue
		}
		let box = TestObservationReport()
		try await outer.provideScope(for: test, testCase: Test.Case.current) { @MainActor in
			box.report = try await registry.executeCase(
				"test-package", observer: ScenarioTestingObserver())
		}
		let report = try #require(box.report)
		#expect(!report.bodyProblems.isEmpty)
		#expect(report.cleanupProblems.isEmpty)
		#expect(shared.lifecycle.serviceStopped)
		#expect(!shared.lifecycle.passed && shared.lifecycle.home == nil)
		#expect(
			report.steps.contains {
				$0.identity.step == "mark successful completion" && $0.status == .skipped
			})
		#expect(
			report.steps.contains {
				$0.identity.step == "teardown private host and registered projects" && $0.status == .passed
			})
		#expect(throws: ScenarioExecutionFailure.self) { try report.requireSuccess() }
	}

	@Test func unexpectedAssertionSkipsSuccessMarkerAndRunsCollectionCleanup() async throws {
		let shared = TestObservationCollection()
		let registry = try ScenarioRegistry([
			ScenarioCollection(
				"test-observation", context: { shared }, setup: [],
				cases: [
					ScenarioCase(
						"test-observation-assertion", context: { _ in TestObservationCase() },
						behaviour: [
							Step("assert") { _ in #expect(Bool(false), "intentional observation assertion") },
							Step("mark successful completion") { _ in shared.passed = true },
						])
				],
				cleanup: [
					CleanupChain(
						"collection cleanup",
						steps: [
							Step("retain stopped fixture") { _ in
								shared.cleaned = true
							}
						])
				])
		])
		let test = try #require(Test.current)
		let outer = IssueHandlingTrait.compactMapIssues { issue in
			issue.comments.contains { $0.rawValue == "intentional observation assertion" }
				? nil : issue
		}
		let box = TestObservationReport()
		try await outer.provideScope(for: test, testCase: Test.Case.current) { @MainActor in
			box.report = try await registry.executeCollection(
				"test-observation", observer: ScenarioTestingObserver())
		}
		let report = try #require(box.report)
		#expect(shared.cleaned && !shared.passed)
		#expect(report.bodyProblems.count == 1 && report.cleanupProblems.isEmpty)
		#expect(
			report.steps.contains {
				$0.identity.step == "mark successful completion" && $0.skipReason == .priorBehaviourFailure
			})
		#expect(throws: ScenarioExecutionFailure.self) { try report.requireSuccess() }
	}
}

@MainActor private final class TestObservationReport { var report: ScenarioReport? }
@MainActor private final class TestObservationCollection: CollectionContext {
	var passed = false
	var cleaned = false
}
@MainActor private final class TestObservationCase: CaseContext {}
