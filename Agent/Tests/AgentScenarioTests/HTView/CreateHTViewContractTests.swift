// @frontmatter:start
// Checks HTView's declarative phases, evidence order, deadlines and unchanged verification boundaries without executing setup.
// @frontmatter:end
import CryptoKit
import Foundation
import Scenario
import Testing

@MainActor private final class HTViewOwnershipFixture: CreateCaseContext {
	var ownership = HTViewSubmissionOwnership()
	let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
	var publishedProject: URL?
	var piCaptured = false
	var stopped = false
	var detached = false
	var joined = false
	var handledProject = false
	var finishSubmission: @MainActor () async -> Void = {}

	override func cleanupResources() async throws {
		try ownership.capture(publishedProject, root: root)
		stopped = true
		detached = true
		await finishSubmission()
		joined = true
		try ownership.capture(publishedProject, root: root)
		try ownership.requireReconciled(piCaptured: piCaptured)
		handledProject = ownership.project != nil
	}
}

@Suite @MainActor struct CreateHTViewContractTests {
	private var directory: URL { URL(fileURLWithPath: #filePath).deletingLastPathComponent() }

	private func source() throws -> String {
		try String(
			contentsOf: directory.appendingPathComponent("CreateHTViewTests.swift"), encoding: .utf8)
	}

	@Test func actualFactoryIsLightweightAndDeclaresEveryPhase() throws {
		let collection = createHTViewCollection()
		let registry = try ScenarioRegistry([collection])
		#expect(registry.collectionNames == ["agent-create"])
		#expect(registry.caseNames == ["create-htview"])
		let names = try #require(
			Mirror(reflecting: collection).children.first { $0.label == "declarations" }?.value
				as? [String])
		#expect(
			names == [
				"confirm every constructed Create case", "emit collection cleanup confirmation",
				"start absolute Create case budget",
				"validate private home and empty library", "assign unchanged HTView prompt",
				"recheck staged credential lifetime", "preflight explicit SDK compiler",
				"submit HTView request", "await settlement and capture owned startup evidence",
				"audit completed Create profile and tools", "audit final-revision authored Test",
				"audit no Parallel and matched Build/Run",
				"capture development identity and audit private storage/activity",
				"independently verify generated WebKit document behavior", "verify development liveness",
				"report production output", "mark HTView behavior passed",
				"release owned Create resources", "await case resource cleanup",
			])
	}

	@Test func partialSubmissionRequiresReconciliationOutsidePolling() throws {
		let text = try source()
		#expect(text.contains("ownership.beginSubmission()\n\t\tsubmission = Task"))
		#expect(text.contains("try captureProject()\n\t\twhile workspace.busy"))
		#expect(text.contains("\n\t\ttry captureProject()\n\t}\n\n\tfunc auditCompletedCreate"))
		let cleanup = try #require(text.range(of: "override func cleanupResources()"))
		let body = text[cleanup.upperBound...]
		let join = try #require(body.range(of: "await submission?.value"))
		let late = body[join.upperBound...]
		#expect(
			late.hasPrefix(
				"\n\t\ttry captureProject()\n\t\ttry ownership.requireReconciled(piCaptured: ownedPi != nil)"
			))
		#expect(!text.contains("ownedProject = project"))
	}

	@Test func alreadySettledSubmissionCapturesProjectWithoutPolling() throws {
		var ownership = HTViewSubmissionOwnership()
		let root = directory
		let published = root.appendingPathComponent(UUID().uuidString)
		ownership.beginSubmission()
		let busy = false
		let session: String? = "completed-session"
		var polls = 0
		try ownership.capture(published, root: root)
		while busy || session == nil { polls += 1 }
		try ownership.capture(published, root: root)
		#expect(polls == 0 && ownership.project == published && ownership.submissionStarted)
		#expect(throws: ScenarioFailure.self) { try ownership.requireReconciled(piCaptured: false) }
		try ownership.requireReconciled(piCaptured: true)
	}

	@Test(arguments: [false, true])
	func cancelledPollingReconcilesLateProjectAndGatesCleanup(piCaptured: Bool) async throws {
		let fixture = HTViewOwnershipFixture()
		fixture.ownership.beginSubmission()
		fixture.piCaptured = piCaptured
		let published = fixture.root.appendingPathComponent(UUID().uuidString)
		fixture.finishSubmission = {
			#expect(fixture.stopped && fixture.detached && !fixture.joined)
			fixture.publishedProject = published
		}
		defer { fixture.finishSubmission = {} }
		if piCaptured {
			try await fixture.cleanup()
			#expect(fixture.cleanupConfirmed && fixture.handledProject)
		} else {
			await #expect(throws: ScenarioFailure.self) { try await fixture.cleanup() }
			#expect(!fixture.cleanupConfirmed && !fixture.handledProject)
			let collection = CreateCollection()
			collection.contexts = [fixture]
			var confirmed = false
			#expect(throws: ScenarioFailure.self) { try collection.confirmCleanup { confirmed = true } }
			#expect(!confirmed)
		}
		#expect(fixture.joined && fixture.ownership.project == published)
	}

	@Test func expiredBudgetSkipsPollingButCannotConfirmUnknownSubmission() async throws {
		let fixture = HTViewOwnershipFixture()
		fixture.budget = .seconds(1)
		let published = fixture.root.appendingPathComponent(UUID().uuidString)
		fixture.finishSubmission = {
			#expect(fixture.stopped && fixture.detached && !Task.isCancelled)
			fixture.publishedProject = published
		}
		defer { fixture.finishSubmission = {} }
		var polled = false, confirmed = false
		let collection = ScenarioCollection(
			"htview-submission-budget", context: CreateCollection.init, setup: [],
			cases: [
				CreateCases.makeCase(
					"htview-submission-expires", context: { fixture }, setup: [],
					behaviour: [
						CreateCases.step("record synthetic submission before expiry") { local in
							local.ownership.beginSubmission()
							try await Task.sleep(for: .seconds(10))
						},
						CreateCases.step("poll synthetic publication") { _ in polled = true },
					])
			], cleanup: [CreateCollection.confirmationChain(emit: { confirmed = true })])
		let report = try await ScenarioRegistry([collection]).executeCase("htview-submission-expires")
		#expect(!report.bodyProblems.isEmpty && !report.cleanupProblems.isEmpty)
		#expect(fixture.ownership.submissionStarted && fixture.ownership.project == published)
		#expect(fixture.joined && !polled && !fixture.handledProject)
		#expect(!fixture.cleanupConfirmed && !confirmed)
	}

	@Test(arguments: [false, true])
	func missingPublicationAfterSubmissionCannotConfirmCleanup(piCaptured: Bool) async {
		let fixture = HTViewOwnershipFixture()
		fixture.ownership.beginSubmission()
		fixture.piCaptured = piCaptured
		await #expect(throws: ScenarioFailure.self) { try await fixture.cleanup() }
		#expect(fixture.joined && !fixture.cleanupConfirmed && !fixture.handledProject)
	}

	@Test func capturedProjectCannotBeReplacedByLatePublication() throws {
		var ownership = HTViewSubmissionOwnership()
		ownership.beginSubmission()
		let first = directory.appendingPathComponent(UUID().uuidString)
		let second = directory.appendingPathComponent(UUID().uuidString)
		try ownership.capture(first, root: directory)
		#expect(throws: ScenarioFailure.self) { try ownership.capture(second, root: directory) }
		#expect(ownership.project == first)
	}

	@Test func preservesExactPrompt() {
		let digest = SHA256.hash(data: Data(htViewCreatePrompt.utf8)).map { String(format: "%02x", $0) }
			.joined()
		#expect(digest == "b6591294f1e921b4c6dd37f4187fdbf93f3ca94a6a3d6fd48f83154cfc9ba634")
	}

	@Test func declaresSeparateSetupBehaviourAndCommonCleanup() throws {
		let text = try source()
		for required in [
			"func createHTViewCollection() -> ScenarioCollection", "CreateCases.makeCase(",
			"setup: [", "behaviour: [", "CreateCollection.confirmationChain()",
			"CreateHTViewContext: CreateCaseContext", "override func cleanupResources()",
		] { #expect(text.contains(required), "Missing declaration: \(required)") }
		#expect(!text.contains("func run()"))
		#expect(!text.contains("print(CreateScenarioIsolation.confirmation)"))
	}

	@Test func namesMeaningfulPhasesInEvidenceOrder() throws {
		let text = try source()
		let names = [
			"validate private home and empty library", "assign unchanged HTView prompt",
			"recheck staged credential lifetime", "preflight explicit SDK compiler",
			"submit HTView request", "await settlement and capture owned startup evidence",
			"audit completed Create profile and tools", "audit final-revision authored Test",
			"audit no Parallel and matched Build/Run",
			"capture development identity and audit private storage/activity",
			"independently verify generated WebKit document behavior", "verify development liveness",
			"report production output", "mark HTView behavior passed",
		]
		var remainder = text[...]
		for name in names {
			let found = remainder.range(of: "CreateCases.step(\"" + name + "\")")
			#expect(found != nil, "Missing or unordered phase: \(name)")
			if let found { remainder = remainder[found.upperBound...] }
		}
	}

	@Test func preservesEntryAndDeadlineStartPoints() throws {
		let text = try source()
		#expect(text.contains("runCreateScenario("))
		#expect(text.contains("caseName: \"create-htview\", testName: \"agentCreateHTViewScenario\""))
		#expect(text.contains("includeVision: false, makeCollection: createHTViewCollection"))
		#expect(text.contains("settlementDeadline = ContinuousClock.now.advanced(by: .seconds(780))"))
		#expect(!text.contains(".seconds(1020)"))
		let submission = try #require(text.range(of: "func submit()"))
		let settlement = try #require(text.range(of: "func awaitSettlement()"))
		let submitBody = text[submission.upperBound..<settlement.lowerBound]
		let task = try #require(submitBody.range(of: "submission = Task { await workspace.submit() }"))
		let deadline = try #require(submitBody.range(of: "settlementDeadline = ContinuousClock.now"))
		#expect(task.upperBound < deadline.lowerBound)
		#expect(submitBody.components(separatedBy: "settlementDeadline =").count == 2)
		#expect(text.components(separatedBy: "runPassed = true").count == 2)
		#expect(
			text.contains("CreateCases.step(\"mark HTView behavior passed\") { $0.runPassed = true }"))
		let compilerStart = try #require(text.range(of: "func preflightCompiler()"))
		let compilerBody = text[compilerStart.upperBound..<submission.lowerBound]
		#expect(compilerBody.contains("try compiler.preflight()"))
		#expect(!compilerBody.contains("workspace.submit()"))
	}

	@Test func retainsAuthoredEvidenceAndIndependentVerifierBoundaries() throws {
		let text = try source()
		for required in [
			"call.started > finalRevision", "call.typedResult?[\"status\"] as? String == \"passed\"",
			"CFGetTypeID(code) != CFBooleanGetTypeID()", "code.doubleValue == 0",
			"try await verifyHTViewWebKit(project: project, compiler: compiler)",
			"Matched Run development app not alive after independent verification",
			"CREATE_PRODUCTION_OUTPUT_EXISTS", "try identity.requireReaped()",
			"try CreateScenarioIsolation.archive(", "if !runPassed ||",
		] { #expect(text.contains(required), "Missing preserved contract: \(required)") }
		for forbidden in [
			"evaluateCreateCounterPreview", "CGWindowListCopyWindowInfo", "verifyCreateNaming",
		] {
			#expect(!text.contains(forbidden))
		}
	}
}
