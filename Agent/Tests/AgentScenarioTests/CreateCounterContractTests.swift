// @frontmatter:start
// Checks Counter and Plan declaration structure, evidence order, deadlines and success gating without live work.
// @frontmatter:end
import Foundation
import Scenario
import Testing

@MainActor private final class CounterAcquisitionFixture: CreateCaseContext {
	let acquisition = CreateCounterAcquisition()
	var publishedProject: URL?
	var publishedSession: URL?
	var piReleased = false
	var events: [String] = []
	var join: @MainActor () async throws -> Void = {}
	var releaseDevelopment: @MainActor () throws -> Void = {}
	var validate: @MainActor (URL) throws -> Void = { _ in }

	override func cleanupResources() async throws {
		try acquisition.observeProject(publishedProject, validate: validate)
		let sessionBeforeStop = publishedSession
		events.append("stop")
		events.append("shutdown")
		try await join()
		events.append("join")
		try acquisition.observeProject(publishedProject, validate: validate)
		try acquisition.requireReleaseEvidence(
			sessionBeforeStop: sessionBeforeStop, sessionAfterJoin: publishedSession,
			piReleased: piReleased)
		if acquisition.project != nil {
			events.append("development")
			try releaseDevelopment()
			events += ["archive", "remove"]
		}
	}
}

@Suite @MainActor struct CreateCounterContractTests {
	private func source() throws -> String {
		try String(
			contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent()
				.appendingPathComponent("CreateCounterTests.swift"), encoding: .utf8)
	}

	private func ordered(_ text: String, _ fragments: [String]) throws {
		var cursor = text.startIndex
		for fragment in fragments {
			let found = try #require(
				text.range(of: fragment, range: cursor..<text.endIndex), "Missing or reordered: \(fragment)"
			)
			cursor = found.upperBound
		}
	}

	private func acquisitionRegistry(
		_ local: CounterAcquisitionFixture, behaviour: [Step<CounterAcquisitionFixture>] = [],
		emit: @escaping () -> Void
	) throws -> ScenarioRegistry {
		try ScenarioRegistry([
			ScenarioCollection(
				"counter-acquisition", context: CreateCollection.init, setup: [],
				cases: [
					CreateCases.makeCase(
						"counter-acquisition-case", context: { local }, setup: [], behaviour: behaviour)
				],
				cleanup: [CreateCollection.confirmationChain(emit: emit)])
		])
	}

	@Test func settledBeforeFirstPollStillCapturesValidatedProject() throws {
		let acquisition = CreateCounterAcquisition()
		let project = URL(fileURLWithPath: "/counter-fixture/\(UUID().uuidString)")
		let session = project.appendingPathComponent(".pi/sessions/session.jsonl")
		acquisition.beginSubmission()
		var validations = 0
		// A settled publication is observed directly, without executing any polling loop.
		let captured = try acquisition.observeProject(project) { candidate in
			#expect(candidate == project)
			validations += 1
		}
		#expect(captured && acquisition.project == project && validations == 1)
		try acquisition.requireReleaseEvidence(
			sessionBeforeStop: session, sessionAfterJoin: session, piReleased: true)
		#expect(throws: ScenarioFailure.self) {
			try acquisition.observeProject(project.appendingPathComponent("replacement")) { _ in }
		}
		#expect(acquisition.project == project)
	}

	@Test func cancellationBetweenSubmissionAndPollingSuppressesConfirmation() async throws {
		let local = CounterAcquisitionFixture()
		var entered = false, emitted = 0
		let registry = try acquisitionRegistry(
			local,
			behaviour: [
				CreateCases.step("register submission") { $0.acquisition.beginSubmission() },
				CreateCases.step("await first ownership poll") { _ in
					entered = true
					try await Task.sleep(for: .seconds(10))
				},
				CreateCases.step("success") { $0.runPassed = true },
			], emit: { emitted += 1 })
		let invocation = Task { try await registry.executeCollection("counter-acquisition") }
		let deadline = ContinuousClock.now.advanced(by: .seconds(2))
		while !entered && ContinuousClock.now < deadline {
			try await Task.sleep(for: .milliseconds(1))
		}
		invocation.cancel()
		let report = try await invocation.value
		#expect(entered && local.acquisition.submissionStarted)
		#expect(!report.bodyProblems.isEmpty && !report.cleanupProblems.isEmpty)
		#expect(!local.runPassed && !local.cleanupConfirmed && emitted == 0)
		#expect(local.events == ["stop", "shutdown", "join"])
	}

	@Test func budgetExpiryAfterSubmissionSuppressesConfirmation() async throws {
		let local = CounterAcquisitionFixture()
		local.budget = .milliseconds(30)
		var emitted = 0
		let registry = try acquisitionRegistry(
			local,
			behaviour: [
				CreateCases.step("register submission") { $0.acquisition.beginSubmission() },
				CreateCases.step("await first ownership poll") { _ in
					try await Task.sleep(for: .seconds(10))
				},
				CreateCases.step("success") { $0.runPassed = true },
			], emit: { emitted += 1 })
		let report = try await registry.executeCollection("counter-acquisition")
		#expect(local.acquisition.submissionStarted && !report.bodyProblems.isEmpty)
		#expect(!report.cleanupProblems.isEmpty && !local.cleanupConfirmed && emitted == 0)
		#expect(!local.runPassed && local.events == ["stop", "shutdown", "join"])
	}

	@Test func lateProjectAndSessionPublicationAreRetainedWithoutConfirmation() async throws {
		let local = CounterAcquisitionFixture()
		let project = URL(fileURLWithPath: "/counter-fixture/\(UUID().uuidString)")
		local.acquisition.beginSubmission()
		var validations = 0, emitted = 0
		local.validate = { _ in validations += 1 }
		local.join = {
			local.publishedProject = project
			local.publishedSession = project.appendingPathComponent("session.jsonl")
		}
		let registry = try acquisitionRegistry(local, emit: { emitted += 1 })
		let report = try await registry.executeCollection("counter-acquisition")
		#expect(local.acquisition.project == project && validations == 1)
		#expect(!report.cleanupProblems.isEmpty && !local.cleanupConfirmed && emitted == 0)
		#expect(local.events == ["stop", "shutdown", "join"])
	}

	@Test func unknownProjectPiOrDevelopmentReleaseCannotConfirmCleanup() async throws {
		for failure in ["project", "pi", "development", "session-changed"] {
			let local = CounterAcquisitionFixture()
			let project = URL(fileURLWithPath: "/counter-fixture/\(UUID().uuidString)")
			local.acquisition.beginSubmission()
			local.publishedProject = failure == "project" ? nil : project
			local.publishedSession = project.appendingPathComponent("session.jsonl")
			local.piReleased = failure != "pi"
			if failure == "session-changed" {
				local.join = {
					local.publishedSession = project.appendingPathComponent("late-session.jsonl")
				}
			}
			if failure == "development" {
				local.releaseDevelopment = {
					throw ScenarioFailure.message("development identity unproven")
				}
			}
			var emitted = 0
			let registry = try acquisitionRegistry(local, emit: { emitted += 1 })
			let report = try await registry.executeCollection("counter-acquisition")
			#expect(!report.cleanupProblems.isEmpty && !local.cleanupConfirmed && emitted == 0)
			#expect(!local.events.contains("archive") && !local.events.contains("remove"))
			#expect(local.events.contains("development") == (failure == "development"))
		}
	}

	@Test func lateProjectWithAlreadyReapedStableSessionReconcilesBeforeDevelopmentRelease()
		async throws
	{
		let local = CounterAcquisitionFixture()
		let project = URL(fileURLWithPath: "/counter-fixture/\(UUID().uuidString)")
		local.acquisition.beginSubmission()
		local.publishedSession = project.appendingPathComponent("session.jsonl")
		local.piReleased = true
		local.join = { local.publishedProject = project }
		var emitted = 0
		let registry = try acquisitionRegistry(local, emit: { emitted += 1 })
		let report = try await registry.executeCollection("counter-acquisition")
		try report.requireSuccess()
		#expect(local.acquisition.project == project && local.cleanupConfirmed && emitted == 1)
		#expect(local.events == ["stop", "shutdown", "join", "development", "archive", "remove"])
	}

	@Test func invalidLateProjectCannotBeRecordedOrReleased() async throws {
		let local = CounterAcquisitionFixture()
		local.acquisition.beginSubmission()
		local.validate = { _ in throw ScenarioFailure.message("foreign project") }
		local.join = { local.publishedProject = URL(fileURLWithPath: "/foreign/project") }
		var emitted = 0
		let registry = try acquisitionRegistry(local, emit: { emitted += 1 })
		let report = try await registry.executeCollection("counter-acquisition")
		#expect(!report.cleanupProblems.isEmpty && !local.cleanupConfirmed && emitted == 0)
		#expect(local.acquisition.project == nil)
		#expect(local.events == ["stop", "shutdown", "join"])
	}

	@Test func declaresReadableCounterAndPlanPhases() throws {
		let text = try source()
		#expect(text.contains("func createCounterCollection(requirePlan: Bool) -> ScenarioCollection"))
		#expect(text.contains("CreateCases.makeCase("))
		#expect(text.contains("setup: ["))
		#expect(text.contains("behaviour: ["))
		#expect(text.contains("cleanup: [CreateCollection.confirmationChain()]"))
		#expect(!text.contains("func run()"))
		#expect(!text.contains("print(CreateScenarioIsolation.confirmation)"))
	}

	@Test func actualFactoriesDeclareEveryPhaseWithoutAcquisition() throws {
		let expected = [
			"confirm every constructed Create case", "emit collection cleanup confirmation",
			"start absolute Create case budget",
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
			"refresh and audit canonical library title", "audit matched development bundle metadata",
			"capture exact development identity and verify private storage",
			"audit completed Test Preview Build Run activity", "review bounded generated sources",
			"compile and execute independent counter assertions",
			"verify development remains alive after independent verification",
			"verify production output remains absent",
			"review last validated Preview through integrated Vision", "mark counter behavior passed",
			"release owned Create resources", "await case resource cleanup",
		]
		for requirePlan in [false, true] {
			// Introspect the real factory only. Never execute setup to discover declarations.
			let collection = createCounterCollection(requirePlan: requirePlan)
			let registry = try ScenarioRegistry([collection])
			#expect(registry.collectionNames == ["agent-create"])
			#expect(registry.caseNames == [requirePlan ? "create-counter-plan" : "create-counter"])
			let actual = try #require(
				Mirror(reflecting: collection).children.first { $0.label == "declarations" }?.value
					as? [String])
			#expect(actual == expected)
		}
		let text = try source()
		let factory = String(
			text.suffix(
				from: try #require(text.range(of: "@MainActor func createCounterCollection")).lowerBound))
		#expect(factory.components(separatedBy: "CreateCases.step(").count == 21)
		#expect(!factory.contains("Step("))
		#expect(!factory.contains("Task {"))
		try ordered(
			factory,
			[
				"setup: [", "$0.validatePrivateLibrary()", "$0.assignPrompt()", "$0.preflightCompiler()",
				"behaviour: [", "$0.submit()", "$0.awaitSettlement()", "$0.auditCompletedSession()",
				"$0.auditPlan()", "$0.auditAuthoredTests()", "$0.auditPreviewAndBuildRun()",
				"$0.auditNaming()", "$0.auditLibraryTitle()", "$0.auditDevelopmentMetadata()",
				"$0.captureDevelopmentAndStorage()", "$0.auditActivity()", "$0.reviewSources()",
				"$0.verifyIndependentBehavior()", "$0.verifyDevelopmentLiveness()",
				"$0.verifyProductionOutputAbsent()", "$0.reviewVision()", "$0.markPassed()",
				"cleanup: [CreateCollection.confirmationChain()]",
			])
	}

	@Test func partialSubmissionCannotConfirmUnknownOwnership() throws {
		let text = try source()
		try ordered(
			text,
			[
				"func submit()", "acquisition.beginSubmission()",
				"submission = Task { await workspace.submit() }",
			])
		try ordered(
			text,
			[
				"func awaitSettlement()", "try captureProject()", "while workspace.busy",
			])
		try ordered(
			text,
			[
				"override func cleanupResources()", "try await cleanupPlan()", "return",
				"try captureProject()", "let sessionBeforeStop = workspace.sessionFile",
				"let stopped = await runtime.stop()", "identity.requireReaped()",
				"try #require(await workspace.shutdown()", "await submission?.value",
				"try captureProject()", "try acquisition.requireReleaseEvidence(",
				"if let project = ownedProject", "stopScaffoldProcess((pid, start)",
				"CreateScenarioIsolation.archive(", "FileManager.default.removeItem(at: project)",
			])
	}

	@Test func exactPromptsAndPreSubmissionSetupRemain() throws {
		let text = try source()
		try ordered(
			text,
			[
				"let home = try CreateScenarioIsolation.requireHome()", "await workspace.refreshLibrary()",
				"$0.isChatOnly && $0.sessions.isEmpty",
				"== home.appendingPathComponent(\".mac-apper\").resolvingSymlinksInPath()",
				"workspace.idea = \"\"\"",
				"Build Pebble Counter, a small native macOS counter app. Use exactly Pebble Counter as its user-visible app name. Show a large count initially zero and buttons labeled Increment, Decrement, and Reset. Increment and Decrement should change the count by one, allow negative counts, and Reset should return it to zero. Keep it simple and fully offline.",
				"Launch the app when it is ready.", "if requirePlan {", "workspace.idea +=",
				"Keep an implementation plan using the plan tool: add tasks before implementing, mark a task in progress while working on it, and update tasks to completed as you finish. Complete all planned tasks before your final response.",
				"func preflightCompiler()", "let compiler = try SDKCompiler.resolve()",
				"try compiler.preflight()",
				"self.compiler = compiler", "func submit()",
				"submission = Task { await workspace.submit() }",
			])
		#expect(text.components(separatedBy: "workspace.idea =").count == 2)
		#expect(text.components(separatedBy: "workspace.idea +=").count == 2)
	}

	@Test func originalGenerationDeadlineAndSettlementOwnershipRemain() throws {
		let text = try source()
		try ordered(
			text,
			[
				"acquisition.beginSubmission()", "submission = Task { await workspace.submit() }",
				"generationDeadline = ContinuousClock.now.advanced(by: .seconds(780))",
				"func captureProject()", "acquisition.observeProject(workspace.project)",
				"project.deletingLastPathComponent().resolvingSymlinksInPath()",
				"== root.resolvingSymlinksInPath()", "UUID(uuidString: project.lastPathComponent) != nil",
				"func captureStartupEvidence()", "try captureProject()", "if ownedProject != nil",
				"if !requirePlan, capturedArguments == nil",
				"ScenarioProcessSnapshot.find(output, sessionPath: file.path)",
				"OwnedProcessIdentity.capture(pid)", "capturedArguments = snapshot.arguments",
				"func awaitSettlement()", "let deadline = try #require(generationDeadline)",
				"try captureProject()", "while workspace.busy || workspace.sessionFile == nil",
				"try Task.checkCancellation()", "try captureStartupEvidence()",
				"ContinuousClock.now < deadline",
				"workspace.busy || workspace.state.status != \"Failed\"",
				"Task.sleep(for: .milliseconds(100))", "try captureStartupEvidence()",
			])
		#expect(text.components(separatedBy: "generationDeadline =").count == 2)
		#expect(text.components(separatedBy: "await submission?.value").count == 2)
	}

	@Test func evidenceOrderAndOriginalAssertionsRemain() throws {
		let text = try source()
		try ordered(
			text,
			[
				"workspace.state.status == \"Completed\"",
				"!workspace.isChatOnly && workspace.selectedAgentID == \"create\"",
				"if requirePlan {", "try auditPlanSessionScope(file: file, project: project)", "} else {",
				"ScenarioSessionAudit.read(Data(contentsOf: file), expectedProject: project.path).profile",
				"== .required", "Missing launch evidence",
				"enabledTools.contains(\"preview\") && enabledTools.contains(\"test\")",
				"enabledTools.contains(\"codemode\")",
				"enabledTools.filter { $0 == \"set_app_name\" }.count == 1",
				"arguments.contains(\"AgentExtensions/parallel-codemode.ts\")",
				"!arguments.contains(\"Web.app\")",
				"arguments.contains(\"DevTools.app/Contents/Resources/PiExtension/Extension.ts\")",
				"verifyCreatePlan(session: file, presentedTasks: workspace.state.tasks)",
				"verifyCounterTesting(session: file, project: project)",
				"verifyPreview(session: file, project: project)",
				"ScenarioToolEvidence(session: file)", "verifyCreateNaming(",
				"expectedName: \"Pebble Counter\"",
				"verifyNamingPlist(project.appendingPathComponent(\"Info.plist\"), expectedName: name)",
				"verifyNoNativeNamingNotification(journal: Data(contentsOf: journal))",
				"canonicalName = name",
				"await workspace.refreshLibrary()", "libraryEntry.title == name",
				"set_app_name · completed",
				"$0.name == \"run\" && $0.succeeded", "$0.finished < $1.finished", "run.typedResult",
				"result[\"relativePath\"] as? String", "result[\"target\"] as? String",
				"namingRelativePath(relative, project: project)",
				"scopedRun + \"/Contents/Info.plist\"", "relative + \"/Contents/MacOS/\" + target",
				"ownedScaffoldProcess(binary)", "CoreData/data.sqlite",
				"FileManager.default.fileExists(atPath: store.path)",
				"for tool in [\"test\", \"preview\", \"build\", \"run\"]", "Missing completed",
				"for path in [",
				"Tests/AppModelTests/ApplicationTests.swift", "text.utf8.count < 100_000",
				"verifyIndependentCounter(project: project, compiler: compiler)",
				"scaffoldProcessStart(launched.pid) == launched.start",
				"scaffoldProcessPath(launched.pid)", "== binary.resolvingSymlinksInPath()",
				"!FileManager.default.fileExists(atPath: output.path)",
				"verifyCounterVision(try #require(preview))",
				"func markPassed()", "runPassed = true", "CREATE_PLAN_BEHAVIOR: passed",
			])
		#expect(text.components(separatedBy: "runPassed = true").count == 2)
	}

	@Test func counterCleanupStillReapsArchivesAndRetainsBeforeRemoval() throws {
		let text = try source()
		try ordered(
			text,
			[
				"override func cleanupResources()", "if requirePlan {", "try await cleanupPlan()", "return",
				"if ownedPi == nil", "OwnedProcessIdentity.capture", "runtime.attach(sessionFile: file)",
				"let stopped = await runtime.stop()", "identity.reap()", "identity.requireReaped()",
				"try #require(stopped", "try #require(await workspace.shutdown()",
				"await submission?.value",
				"project.appendingPathComponent(\".mac-apper/DevBuild\")", "scaffoldProcessStart(pid)",
				"stopScaffoldProcess((pid, start), binary:", "CreateScenarioIsolation.archive(",
				"if !runPassed || ProcessInfo.processInfo.environment[\"AGENT_CREATE_KEEP_PROJECT\"] == \"1\"",
				"CREATE_RETAINED_PROJECT:", "FileManager.default.removeItem(at: project)",
			])
		#expect(!text.contains("cleanupConfirmed = true"))
		#expect(!text.contains("print(CreateScenarioIsolation.confirmation)"))
		#expect(text.components(separatedBy: "includeVision: true").count == 3)
		#expect(text.contains("caseName: \"create-counter\", testName: \"agentCreateCounterScenario\""))
		#expect(
			text.contains("caseName: \"create-counter-plan\", testName: \"agentCreatePlanScenario\""))
	}
}
