// @frontmatter:start
// Tests allocation-free Plan configuration and independent case-owned fixture retention without XPC startup.
// @frontmatter:end
import Foundation
import Scenario
import ScenarioTesting
@_spi(Experimental) import Testing

@MainActor private final class PlanObservationReport {
	var report: ScenarioReport?
}

@Suite @MainActor struct DevToolsPlanIsolationTests {
	@Test func configurationAndContextsAllocateNoFixtures() throws {
		let registry = try ScenarioRegistry([devToolsPlanCollection()])
		#expect(
			registry.caseNames == [
				"plan-initial-tasks", "plan-lifecycle", "plan-rejections", "plan-project-isolation",
			])
		let collection = DevToolsPlanCollection()
		let first = DevToolsPlanCase(collection), second = DevToolsPlanCase(collection)
		#expect(first.lifecycle !== second.lifecycle)
		#expect(first.lifecycle.home == nil && second.lifecycle.home == nil)
		#expect(first.lifecycle.host == nil && second.lifecycle.host == nil)
		#expect(first.lifecycle.projects == nil && second.lifecycle.projects == nil)
	}

	@Test func unknownSelectorsRejectBeforeAcquisition() async throws {
		let registry = try ScenarioRegistry([devToolsPlanCollection()])
		await #expect(throws: ScenarioFailure.self) {
			try await registry.executeCase("plan-unknown", observer: ScenarioTestingObserver())
		}
		await #expect(throws: ScenarioFailure.self) {
			try await registry.executeCollection("plan-unknown", observer: ScenarioTestingObserver())
		}
	}

	@Test func observedFailureSkipsSuccessMarkerAndRetainsStoppedFixtures() async throws {
		let context = DevToolsPlanCase(DevToolsPlanCollection())
		var cleanupRan = false
		let collection = ScenarioCollection(
			"offline-plan-observation", context: DevToolsPlanCollection.init,
			setup: [],
			cases: [
				ScenarioCase(
					"offline-plan-failure", context: { _ in context },
					setup: [
						Step("prepare private fixtures without starting a host") { context in
							// Stop before host preparation; only private test-owned fixtures exist.
							#expect(throws: (any Error).self) {
								try context.lifecycle.setup(beforeHost: { throw ScenarioFailure.message("offline") }
								)
							}
							context.primary = try context.projects.create()
						}
					],
					behaviour: [
						Step("observe a nonthrowing assertion failure") { _ in
							let actual = "rejected"
							#expect(actual == "accepted", "intentional Plan observation fixture")
						},
						Step("confirm all assertions passed") { $0.lifecycle.passed = true },
					],
					cleanup: [
						CleanupChain(
							"release through existing lifecycle gates",
							steps: [
								Step("stop and retain failed fixtures") {
									cleanupRan = true
									try $0.lifecycle.teardown()
								}
							])
					])
			], cleanup: [])
		let registry = try ScenarioRegistry([collection])
		let test = try #require(Test.current)
		// Suppress only the deliberate negative fixture after the inner observer sees it.
		let outer = IssueHandlingTrait.compactMapIssues { issue in
			issue.comments.contains { $0.rawValue == "intentional Plan observation fixture" }
				? nil : issue
		}
		let result = PlanObservationReport()
		try await outer.provideScope(for: test, testCase: Test.Case.current) { @MainActor in
			result.report = try await registry.executeCase(
				"offline-plan-failure", observer: ScenarioTestingObserver())
		}
		let report = try #require(result.report)
		#expect(throws: ScenarioExecutionFailure.self) { try report.requireSuccess() }
		#expect(report.bodyProblems.contains { $0.origin == .assertion })
		#expect(report.cleanupProblems.isEmpty)
		#expect(
			report.steps.contains {
				$0.identity.step == "confirm all assertions passed"
					&& $0.skipReason == .priorBehaviourFailure
			})
		#expect(cleanupRan)
		#expect(!context.lifecycle.passed)
		#expect(context.lifecycle.serviceStopped)
		let home = try #require(context.lifecycle.home)
		let project = try #require(context.primary)
		#expect(FileManager.default.fileExists(atPath: home.directory.path))
		#expect(FileManager.default.fileExists(atPath: project.url.path))
		// Remove only this stopped regression fixture after checking failure retention.
		context.lifecycle.passed = true
		try context.lifecycle.teardown()
		#expect(!FileManager.default.fileExists(atPath: home.directory.path))
	}

	@Test func failedCaseCannotDeleteLaterCaseFixtures() throws {
		let collection = DevToolsPlanCollection()
		let first = DevToolsPlanCase(collection), second = DevToolsPlanCase(collection)
		for context in [first, second] {
			#expect(throws: (any Error).self) {
				try context.lifecycle.setup(beforeHost: { throw ScenarioFailure.message("partial setup") })
			}
		}
		let firstHome = try #require(first.lifecycle.home)
		let secondHome = try #require(second.lifecycle.home)
		#expect(firstHome.directory.path != secondHome.directory.path)
		let firstProject = try first.projects.create()
		let secondProject = try second.projects.create()
		let auxiliary = try second.projects.create()
		try first.lifecycle.teardown()
		#expect(FileManager.default.fileExists(atPath: firstProject.url.path))
		#expect(FileManager.default.fileExists(atPath: secondProject.url.path))
		#expect(FileManager.default.fileExists(atPath: auxiliary.url.path))
		second.lifecycle.passed = true
		try second.lifecycle.teardown()
		#expect(!FileManager.default.fileExists(atPath: secondHome.directory.path))
		#expect(FileManager.default.fileExists(atPath: firstHome.directory.path))
		// Only stopped test-owned retained fixtures are removed by this regression.
		first.lifecycle.passed = true
		try first.lifecycle.teardown()
	}

	@Test func terminalArchiveOutlivesSelectiveProjectDeletion() throws {
		let lifecycle = DevToolsScenarioLifecycle()
		#expect(throws: (any Error).self) {
			try lifecycle.setup(beforeHost: { throw ScenarioFailure.message("partial setup") })
		}
		let home = try #require(lifecycle.home)
		let projects = try #require(lifecycle.projects)
		let fixture = try projects.create(), auxiliary = try projects.create()
		let archive = try home.privateDirectory("previews").appendingPathComponent("owned.txt")
		try Data("archive evidence".utf8).write(to: archive)
		try lifecycle.stopServiceRetainingFixtures()
		try lifecycle.removeProjectAfterServiceStop(fixture.url)
		#expect(try Data(contentsOf: archive) == Data("archive evidence".utf8))
		#expect(FileManager.default.fileExists(atPath: auxiliary.url.path))
		try lifecycle.teardown()
		#expect(FileManager.default.fileExists(atPath: archive.path))
		lifecycle.passed = true
		try lifecycle.teardown()
		#expect(!FileManager.default.fileExists(atPath: archive.path))
	}

	@Test func selectiveRemovalFailureKeepsMembership() throws {
		let home = try IsolatedScenarioHome()
		let projects = DevToolsScenarioProjects(root: try home.privateDirectory(".mac-apper"))
		let fixture = try projects.create()
		try FileManager.default.removeItem(at: fixture.url)
		try FileManager.default.createSymbolicLink(at: fixture.url, withDestinationURL: home.directory)
		#expect(throws: (any Error).self) { try projects.remove(fixture.url) }
		try FileManager.default.removeItem(at: fixture.url)
		try FileManager.default.createDirectory(at: fixture.url, withIntermediateDirectories: false)
		try projects.remove(fixture.url)
		try projects.remove()
		try home.remove(cleanupConfirmed: true)
	}

	@Test func allPartialWritesRemainOwned() throws {
		let home = try IsolatedScenarioHome()
		let root = try home.privateDirectory(".mac-apper")
		let projects = DevToolsScenarioProjects(root: root)
		_ = try projects.create()
		for _ in 0..<3 {
			#expect(throws: (any Error).self) {
				_ = try projects.create(afterDirectory: { _ in throw ScenarioFailure.message("partial") })
			}
		}
		#expect(try FileManager.default.contentsOfDirectory(atPath: root.path).count == 4)
		try projects.remove()
		#expect(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
		try home.remove(cleanupConfirmed: true)
	}

	@Test func defaultCompletionIncludesIdentifiedRejection() throws {
		let state = DevToolsScenarioLifecycle.RequestState()
		var captures = 0
		// The real host's expectRejected returns Void only after envelope/IDs/code validation.
		try state.perform(capture: { captures += 1 }) {}
		#expect(state.requestConfirmed && captures == 1)
		#expect(throws: (any Error).self) {
			try state.perform(capture: { captures += 1 }) {
				throw ScenarioFailure.message("transport exception")
			}
		}
		#expect(!state.requestConfirmed && captures == 1)
		var signaled = false
		#expect(throws: (any Error).self) { try state.stop { signaled = true } }
		#expect(!signaled)
	}

	@Test func missingIdentityBlocksConfirmationAndStop() throws {
		let state = DevToolsScenarioLifecycle.RequestState()
		#expect(throws: (any Error).self) {
			try state.perform(capture: { throw ScenarioFailure.message("missing immutable identity") }) {
				1
			}
		}
		#expect(!state.requestConfirmed)
		var stopped = false
		#expect(throws: (any Error).self) { try state.stop { stopped = true } }
		#expect(!stopped)
	}

	@Test func cancelledTaskCanConfirmSynchronousStop() async throws {
		let task = Task { @MainActor in
			let state = DevToolsScenarioLifecycle.RequestState()
			_ = try state.perform(capture: {}) { 1 }
			withUnsafeCurrentTask { $0?.cancel() }
			try state.stop {}
			return state.serviceStopped
		}
		#expect(try await task.value)
	}
}
