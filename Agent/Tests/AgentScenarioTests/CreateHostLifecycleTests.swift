// @frontmatter:start
// Exercises injected Create host ownership, invocation evidence and gated retention without real hosts.
// @frontmatter:end
import Foundation
import Scenario
import ScenarioTesting
@_spi(Experimental) import Testing

@MainActor private final class CreateHostFixture {
	var events: [String] = []
	var fail: String?
	var observedFailure: String?
	var includeVision = true
	var output =
		"Test selectedCreate() started.\nTest selectedCreate() passed\n"
		+ CreateScenarioIsolation.confirmation
	var status: Int32 = 0
	var missingResult = false
	var removeFixtures: Bool?
	func event(_ name: String) throws {
		events.append(name)
		if fail == name { throw ScenarioFailure.message(name) }
		if observedFailure == name { #expect(Bool(false), "create-host-observed-fixture") }
	}
	var operations: CreateHostOperations {
		CreateHostOperations(
			prepareHome: { try self.event("home") },
			prepareHost: { vision in
				#expect(vision == self.includeVision); try self.event("host")
			},
			validateCredential: { try self.event("credential") },
			invoke: {
				try self.event("invoke")
				return self.missingResult ? nil : CreateHostResult(status: self.status, output: self.output)
			},
			stopAgent: { try self.event("agent") }, stopDevTools: { try self.event("devtools") },
			removeHost: { try self.event("remove-host") },
			finishHost: { confirmed, remove, stop, removeHost in
				#expect(confirmed)
				try stop()
				try self.event("scrub")
				self.removeFixtures = remove
				if remove { try removeHost(); try self.event("remove-home") }
				return remove
			},
			removeUnstartedHome: { try self.event("remove-unstarted-home") })
	}
	func run(keep: Bool = false) async throws -> ScenarioReport {
		let context = CreateHostContext(
			testName: "selectedCreate", includeVision: includeVision, keepProject: keep,
			operations: operations)
		let registry = try ScenarioRegistry([createHostCollection(context)])
		return try await registry.executeCollection(
			"agent-create-host", observer: ScenarioTestingObserver())
	}
}

@Suite @MainActor struct CreateHostLifecycleTests {
	@Test func successStopsInOrderThenScrubsAndRemoves() async throws {
		let fixture = CreateHostFixture()
		try await fixture.run().requireSuccess()
		#expect(
			fixture.events == [
				"home", "host", "credential", "invoke", "agent", "devtools", "scrub", "remove-host",
				"remove-home",
			])
		#expect(fixture.removeFixtures == true)
	}

	@Test func htViewSelectionDoesNotEnableVision() async throws {
		let fixture = CreateHostFixture()
		fixture.includeVision = false
		try await fixture.run().requireSuccess()
	}

	@Test func observedInvocationFailureSuppressesValidationAndRemoval() async throws {
		let fixture = CreateHostFixture()
		fixture.observedFailure = "invoke"
		let suppress = IssueHandlingTrait.compactMapIssues { issue in
			if issue.comments.contains(where: { $0.rawValue == "create-host-observed-fixture" }) {
				return nil
			}
			return issue
		}
		let test = try #require(Test.current)
		var report: ScenarioReport?
		try await suppress.provideScope(for: test, testCase: Test.Case.current) { @MainActor in
			report = try await fixture.run()
		}
		#expect(!(try #require(report)).bodyProblems.isEmpty)
		#expect(fixture.removeFixtures == false && fixture.events.last == "scrub")
	}

	@Test func partialPreparationRemovesOnlyProvenUnstartedHome() async throws {
		for failure in ["home", "host"] {
			let fixture = CreateHostFixture(); fixture.fail = failure
			let report = try await fixture.run()
			#expect(!report.bodyProblems.isEmpty)
			#expect(!fixture.events.contains("invoke"))
			#expect(fixture.events.contains("remove-unstarted-home") == (failure == "host"))
		}
	}

	@Test func invocationThrowOrMissingResultRetainsEverything() async throws {
		for missing in [false, true] {
			let fixture = CreateHostFixture()
			if missing { fixture.missingResult = true } else { fixture.fail = "invoke" }
			let report = try await fixture.run()
			#expect(!report.bodyProblems.isEmpty && !report.cleanupProblems.isEmpty)
			#expect(fixture.events == ["home", "host", "credential", "invoke"])
		}
	}

	@Test func statusAndExactSelectedMarkersCannotReplaceInnerConfirmation() async throws {
		let fixture = CreateHostFixture()
		fixture.output = "Test selectedCreate() started.\nTest selectedCreate() passed"
		let report = try await fixture.run()
		#expect(!report.cleanupProblems.isEmpty)
		#expect(!fixture.events.contains("agent") && !fixture.events.contains("scrub"))
	}

	@Test func missingSelectedStartOrPassAndFailedStatusRetainAfterSafeScrub() async throws {
		for mutation in [0, 1, 2] {
			let fixture = CreateHostFixture()
			if mutation == 0 {
				fixture.output = fixture.output.replacingOccurrences(
					of: "Test selectedCreate() started.", with: "Test other() started.")
			}
			if mutation == 1 {
				fixture.output = fixture.output.replacingOccurrences(
					of: "Test selectedCreate() passed", with: "Test other() passed")
			}
			if mutation == 2 { fixture.status = 1 }
			let report = try await fixture.run()
			#expect(!report.bodyProblems.isEmpty && report.cleanupProblems.isEmpty)
			#expect(fixture.removeFixtures == false)
			#expect(fixture.events.suffix(3) == ["agent", "devtools", "scrub"])
		}
	}

	@Test func serviceFailureBlocksScrubAndRemoval() async throws {
		for failure in ["agent", "devtools"] {
			let fixture = CreateHostFixture(); fixture.fail = failure
			let report = try await fixture.run()
			#expect(!report.cleanupProblems.isEmpty)
			#expect(!fixture.events.contains("scrub") && !fixture.events.contains("remove-host"))
			#expect(fixture.events.contains("devtools") == (failure == "devtools"))
		}
	}

	@Test func keepRetainsSuccessfulFixturesAfterScrub() async throws {
		let fixture = CreateHostFixture()
		try await fixture.run(keep: true).requireSuccess()
		#expect(fixture.removeFixtures == false)
		#expect(fixture.events.last == "scrub")
	}

	@Test func credentialFailureBeforeInvocationStillOwnsHostAndHome() async throws {
		let fixture = CreateHostFixture(); fixture.fail = "credential"
		let report = try await fixture.run()
		#expect(!report.bodyProblems.isEmpty && report.cleanupProblems.isEmpty)
		#expect(!fixture.events.contains("invoke"))
		#expect(fixture.events.suffix(3) == ["agent", "devtools", "scrub"])
		#expect(fixture.removeFixtures == false)
	}
}
