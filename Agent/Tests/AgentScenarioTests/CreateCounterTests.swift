// @frontmatter:start
// Exercises live Create counter generation and optional plan progress with agent-authored Swift Testing, Test/Preview, independent model, launch, and Gemini checks.
// @frontmatter:end
import AgentMacosClient
import AgentMacosClientModel
import AgentScenarioSupport
import Darwin
import Foundation
import Scenario
import Testing

// Records acquisition independently of settlement polling. A stopped runtime alone cannot prove
// that an unstructured submission did not publish a new session while cleanup was awaiting it.
@MainActor final class CreateCounterAcquisition {
	private(set) var submissionStarted = false
	private(set) var project: URL?

	func beginSubmission() { submissionStarted = true }

	@discardableResult func observeProject(
		_ candidate: URL?, validate: (URL) throws -> Void
	) throws -> Bool {
		guard
			let candidate
		else { return false }
		try validate(candidate)
		if let project {
			guard
				project == candidate
			else {
				throw ScenarioFailure.message("Create project changed during submission; retain fixtures")
			}
			return false
		}
		project = candidate
		return true
	}

	func requireReleaseEvidence(
		sessionBeforeStop: URL?, sessionAfterJoin: URL?, piReleased: Bool
	) throws {
		if !submissionStarted && project == nil && sessionBeforeStop == nil
			&& sessionAfterJoin == nil && !piReleased
		{
			return
		}
		guard
			project != nil
		else {
			throw ScenarioFailure.message(
				"Create submission ownership unknown; retain host/home and any development children")
		}
		guard
			let sessionBeforeStop,
			sessionBeforeStop == sessionAfterJoin,
			piReleased
		else {
			throw ScenarioFailure.message(
				"Create submission published an unproven session or Pi release; retain project/host/home")
		}
	}
}

@MainActor private final class CreateCounterContext: CreateCaseContext {
	let adapter = AgentServiceXPCAdapter()
	let runtime: AgentXPCRuntime
	let workspace: WorkspaceSession
	var submission: Task<Void, Never>?
	private let acquisition = CreateCounterAcquisition()
	var ownedProject: URL? { acquisition.project }
	var ownedPi: OwnedProcessIdentity?
	let requirePlan: Bool
	private var home: URL?
	private var compiler: SDKCompiler?
	private var generationDeadline: ContinuousClock.Instant?
	private var capturedArguments: String?
	private var preview: VerifiedCounterPreview?
	private var evidence: ScenarioToolEvidence?
	private var canonicalName: String?
	private var binary: URL?
	private var launched: (pid: Int32, start: UInt64)?

	init(requirePlan: Bool = false) {
		self.requirePlan = requirePlan
		runtime = AgentXPCRuntime(transport: adapter)
		workspace = WorkspaceSession(
			runtime: runtime, workspaceStore: AgentXPCWorkspaceStore(transport: adapter))
		workspace.selectAgent("create")
		super.init()
	}

	func validatePrivateLibrary() async throws {
		let home = try CreateScenarioIsolation.requireHome()
		await workspace.refreshLibrary()
		try #require(
			workspace.library.allSatisfy {
				$0.isChatOnly && $0.sessions.isEmpty
					&& $0.project.deletingLastPathComponent().resolvingSymlinksInPath()
						== home.appendingPathComponent(".mac-apper").resolvingSymlinksInPath()
			})
		self.home = home
	}

	func assignPrompt() throws {
		workspace.idea = """
			Build Pebble Counter, a small native macOS counter app. Use exactly Pebble Counter as its user-visible app name. Show a large count initially zero and buttons labeled Increment, Decrement, and Reset. Increment and Decrement should change the count by one, allow negative counts, and Reset should return it to zero. Keep it simple and fully offline.
			Launch the app when it is ready.
			"""
		if requirePlan {
			workspace.idea += """

				Keep an implementation plan using the plan tool: add tasks before implementing, mark a task in progress while working on it, and update tasks to completed as you finish. Complete all planned tasks before your final response.
				"""
		}
	}

	func preflightCompiler() throws {
		let compiler = try SDKCompiler.resolve()
		try compiler.preflight()
		self.compiler = compiler
	}

	func submit() throws {
		acquisition.beginSubmission()
		submission = Task { await workspace.submit() }
		generationDeadline = ContinuousClock.now.advanced(by: .seconds(780))
	}

	func captureProject() throws {
		let captured = try acquisition.observeProject(workspace.project) { project in
			let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
				".mac-apper")
			try #require(
				project.deletingLastPathComponent().resolvingSymlinksInPath()
					== root.resolvingSymlinksInPath())
			try #require(UUID(uuidString: project.lastPathComponent) != nil)
		}
		if captured, let project = ownedProject { print("CREATE_PROJECT: \(project.path)") }
	}

	func captureStartupEvidence() throws {
		try captureProject()
		if ownedProject != nil {
			if !requirePlan, capturedArguments == nil, let file = workspace.sessionFile {
				let output = try command("/bin/ps", ["-ww", "-axo", "pid=,command="])
				if let snapshot = try? ScenarioProcessSnapshot.find(output, sessionPath: file.path),
					let pid = Int32(snapshot.pid)
				{
					ownedPi = try OwnedProcessIdentity.capture(pid)
					capturedArguments = snapshot.arguments
					let identity = try #require(ownedPi)
					print(
						"CREATE_PI_IDENTITY: pid=\(identity.pid) start=\(identity.start) path=\(identity.path)"
					)
				}
			}
		}
	}

	func awaitSettlement() async throws {
		let deadline = try #require(generationDeadline)
		try captureProject()
		while workspace.busy || workspace.sessionFile == nil {
			try Task.checkCancellation()
			try captureStartupEvidence()
			try #require(
				ContinuousClock.now < deadline, "Create deadline exceeded: \(workspace.state.status)")
			try #require(
				workspace.busy || workspace.state.status != "Failed", "Create failed: \(workspace.activity)"
			)
			try await Task.sleep(for: .milliseconds(100))
		}
		// Settlement may have completed before the first poll or during its final sleep.
		try captureStartupEvidence()
	}

	func auditCompletedSession() throws {
		let project = try #require(ownedProject)
		let file = try #require(workspace.sessionFile)
		try #require(
			workspace.state.status == "Completed", "\(workspace.state.status): \(workspace.activity)")
		#expect(!workspace.isChatOnly && workspace.selectedAgentID == "create")
		if requirePlan {
			try auditPlanSessionScope(file: file, project: project)
		} else {
			#expect(
				try ScenarioSessionAudit.read(Data(contentsOf: file), expectedProject: project.path).profile
					== .required)
			let arguments = try #require(capturedArguments, "Missing launch evidence")
			let tools = try #require(
				arguments.range(of: #"--tools\s+([^\s]+)"#, options: .regularExpression))
			let enabledTools =
				arguments[tools].split(whereSeparator: \.isWhitespace).last?
				.split(separator: ",").map(String.init) ?? []
			#expect(
				enabledTools.contains("preview") && enabledTools.contains("test")
					&& enabledTools.contains("codemode"))
			try #require(enabledTools.filter { $0 == "set_app_name" }.count == 1)
			#expect(arguments.contains("AgentExtensions/parallel-codemode.ts"))
			#expect(!arguments.contains("Web.app"))
			#expect(arguments.contains("DevTools.app/Contents/Resources/PiExtension/Extension.ts"))
		}
		print("CREATE_REPLY: \(workspace.messages.last(where: { !$0.isUser })?.text ?? "")")
		print("CREATE_ACTIVITY: \(workspace.state.liveDetails.joined(separator: "\n"))")
	}

	func auditPlan() throws {
		let file = try #require(workspace.sessionFile)
		if requirePlan {
			try verifyCreatePlan(session: file, presentedTasks: workspace.state.tasks)
		}
	}

	func auditAuthoredTests() async throws {
		let project = try #require(ownedProject)
		let file = try #require(workspace.sessionFile)
		try await verifyCounterTesting(session: file, project: project)
	}

	func auditPreviewAndBuildRun() throws {
		let project = try #require(ownedProject)
		let file = try #require(workspace.sessionFile)
		preview = try verifyPreview(session: file, project: project)
		evidence = try ScenarioToolEvidence(session: file)
	}

	func auditNaming() throws {
		let project = try #require(ownedProject)
		let file = try #require(workspace.sessionFile)
		let evidence = try #require(evidence)
		let name = try verifyCreateNaming(
			evidence: evidence, project: project, expectedName: "Pebble Counter")
		try verifyNamingPlist(project.appendingPathComponent("Info.plist"), expectedName: name)
		let journal = project.appendingPathComponent(".pi/agent-events/\(file.lastPathComponent)")
		try verifyNoNativeNamingNotification(journal: Data(contentsOf: journal))
		canonicalName = name
	}

	func auditLibraryTitle() async throws {
		let project = try #require(ownedProject)
		let name = try #require(canonicalName)
		await workspace.refreshLibrary()
		let libraryEntry = try #require(workspace.library.first { $0.project == project })
		try #require(libraryEntry.title == name)
		try #require(workspace.state.liveDetails.contains { $0.hasPrefix("set_app_name · completed") })
	}

	func auditDevelopmentMetadata() throws {
		let project = try #require(ownedProject)
		let evidence = try #require(evidence)
		let name = try #require(canonicalName)
		let run = try #require(
			evidence.calls.filter { $0.name == "run" && $0.succeeded }.max(by: {
				$0.finished < $1.finished
			}))
		let result = try #require(run.typedResult)
		let relative = try #require(result["relativePath"] as? String)
		let target = try #require(result["target"] as? String)
		let scopedRun = try namingRelativePath(relative, project: project)
		try verifyNamingPlist(
			project.appendingPathComponent(scopedRun + "/Contents/Info.plist"), expectedName: name)
		print("CREATE_NAMING: canonical/project/matched-development/library = \(name)")
		let binary = project.appendingPathComponent(relative + "/Contents/MacOS/" + target)
		self.binary = binary
	}

	func captureDevelopmentAndStorage() async throws {
		let project = try #require(ownedProject)
		let home = try #require(home)
		let binary = try #require(binary)
		let launched = try await ownedScaffoldProcess(binary)
		print("CREATE_RUN_IDENTITY: pid=\(launched.pid) start=\(launched.start) path=\(binary.path)")
		let store = home.appendingPathComponent(
			"Library/Application Support/MacApperGenerated/\(project.lastPathComponent)/CoreData/data.sqlite"
		)
		try #require(
			FileManager.default.fileExists(atPath: store.path),
			"Development production storage must be in the owned home")
		print("CREATE_ISOLATED_STORAGE: \(store.path)")
		self.launched = launched
	}

	func auditActivity() throws {
		for tool in ["test", "preview", "build", "run"] {
			#expect(
				workspace.state.liveDetails.contains(where: { $0.hasPrefix("\(tool) · completed") }),
				"Missing completed \(tool) activity")
		}
	}

	func reviewSources() throws {
		let project = try #require(ownedProject)
		for path in [
			"Package.swift", "app-manifest.json", "Sources/AppModel/ApplicationModel.swift",
			"Sources/AppViews/ApplicationRoot.swift", "Tests/AppModelTests/ApplicationTests.swift",
		] {
			let text = try String(contentsOf: project.appendingPathComponent(path), encoding: .utf8)
			try #require(text.utf8.count < 100_000)
			print("CREATE_SOURCE \(path):\n\(text)")
		}
	}

	func verifyIndependentBehavior() throws {
		let project = try #require(ownedProject)
		let compiler = try #require(compiler)
		// Independent behavioral assertions, not merely the generated agent's own tests.
		try verifyIndependentCounter(project: project, compiler: compiler)
		print("CREATE_MODEL_TESTS: passed (generated tests plus independent counter assertions)")
	}

	func verifyDevelopmentLiveness() throws {
		let launched = try #require(launched)
		let binary = try #require(binary)
		try #require(scaffoldProcessStart(launched.pid) == launched.start)
		try #require(
			scaffoldProcessPath(launched.pid).map { URL(fileURLWithPath: $0).resolvingSymlinksInPath() }
				== binary.resolvingSymlinksInPath(),
			"Matched Run development app not alive after independent verification")
	}

	func verifyProductionOutputAbsent() throws {
		let project = try #require(ownedProject)
		let output = project.deletingLastPathComponent().appendingPathComponent(
			"output/\(project.lastPathComponent)")
		print("CREATE_PRODUCTION_OUTPUT_EXISTS: \(FileManager.default.fileExists(atPath: output.path))")
		try #require(
			!FileManager.default.fileExists(atPath: output.path),
			"Metadata naming and normal development Run must not create a production package")
	}

	func reviewVision() async throws {
		try await verifyCounterVision(try #require(preview))
	}

	func markPassed() throws {
		runPassed = true
		if requirePlan { print("CREATE_PLAN_BEHAVIOR: passed") }
	}

	private func cleanupPlan() async throws {
		let outcome = await finishPlanLifecycle(
			attach: {
				if !self.workspace.connected, let file = self.workspace.sessionFile {
					guard
						let project = self.ownedProject
					else { throw ScenarioFailure.message("Missing owned Plan project for attach") }
					try auditPlanSessionScope(file: file, project: project)
					_ = try await self.runtime.attach(sessionFile: file)
				}
			}, stop: { await self.runtime.stop() },
			shutdown: { await self.workspace.shutdown() },
			completeSubmission: { await self.submission?.value })
		print(
			"CREATE_PLAN_CLEANUP_UNCONFIRMED: behavior=\(runPassed ? "passed" : "not-confirmed") retained-fixtures; not a full pass"
		)
		try #require(
			outcome.cleanupConfirmed,
			"Plan cleanup unconfirmed; retain project/host/home: \((outcome.failures + ["Pi/descendant quiescence not confirmed"]).joined(separator: "; "))"
		)
	}

	override func cleanupResources() async throws {
		if requirePlan {
			try await cleanupPlan()
			return
		}
		try captureProject()
		let sessionBeforeStop = workspace.sessionFile
		// Never delete a partial-start project if its Pi identity was not captured.
		if ownedPi == nil, let file = workspace.sessionFile {
			let output = try command("/bin/ps", ["-ww", "-axo", "pid=,command="])
			let snapshot = try ScenarioProcessSnapshot.find(output, sessionPath: file.path)
			ownedPi = try OwnedProcessIdentity.capture(try #require(Int32(snapshot.pid)))
		}
		if !workspace.connected, let file = workspace.sessionFile {
			_ = try await runtime.attach(sessionFile: file)
		}
		let stopped = await runtime.stop()
		if let identity = ownedPi {
			try identity.reap()
			try identity.requireReaped()
			print(
				"CREATE_PI_CLEANUP: pid=\(identity.pid) start=\(identity.start) path=\(identity.path) reaped"
			)
		}
		try #require(stopped, "Pi stop failed; retain fixtures")
		try #require(await workspace.shutdown(), "Client detach failed")
		await submission?.value
		// Shutdown and joining submission can publish a project/session after the last poll.
		try captureProject()
		try acquisition.requireReleaseEvidence(
			sessionBeforeStop: sessionBeforeStop, sessionAfterJoin: workspace.sessionFile,
			piReleased: ownedPi != nil)
		if let project = ownedProject {
			let processes = try command("/bin/ps", ["-axo", "pid="])
			let prefix =
				project.appendingPathComponent(".mac-apper/DevBuild").resolvingSymlinksInPath().path + "/"
			for pid in processes.split(separator: "\n").compactMap({
				Int32($0.trimmingCharacters(in: .whitespaces))
			}) {
				guard
					let path = scaffoldProcessPath(pid),
					URL(fileURLWithPath: path).resolvingSymlinksInPath().path.hasPrefix(prefix)
				else { continue }
				let start = try #require(scaffoldProcessStart(pid))
				try await stopScaffoldProcess((pid, start), binary: URL(fileURLWithPath: path))
			}
			try CreateScenarioIsolation.archive(
				project: project, home: CreateScenarioIsolation.requireHome())
			if !runPassed || ProcessInfo.processInfo.environment["AGENT_CREATE_KEEP_PROJECT"] == "1" {
				print("CREATE_RETAINED_PROJECT: \(project.path)")
			} else {
				try FileManager.default.removeItem(at: project)
			}
		}
	}
}

private func command(_ executable: String, _ arguments: [String]) throws -> String {
	let process = Process()
	let pipe = Pipe()
	process.executableURL = URL(fileURLWithPath: executable)
	process.arguments = arguments
	process.standardOutput = pipe
	process.standardError = FileHandle.nullDevice
	try process.run()
	let data = pipe.fileHandleForReading.readDataToEndOfFile()
	process.waitUntilExit()
	try #require(process.terminationStatus == 0 && data.count <= 4_194_304)
	return String(decoding: data, as: UTF8.self)
}

// Scope-only evidence. Runtime/model/extension policy belongs to production, not this driver.
// Validation is point-in-time, not a filesystem lease against later replacement.
func auditPlanSessionScope(file: URL, project: URL) throws {
	let parent = file.deletingLastPathComponent()
	guard
		try ScenarioDirectoryIdentity.read(parent.path)
			== ScenarioDirectoryIdentity.read(project.appendingPathComponent(".pi/sessions").path)
	else { throw ScenarioFailure.message("Plan session outside scoped sessions directory") }
	let directory = open(parent.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
	guard
		directory >= 0
	else { throw ScenarioFailure.message("Cannot open Plan sessions directory") }
	defer { Darwin.close(directory) }
	let descriptor = openat(
		directory, file.lastPathComponent, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
	guard
		descriptor >= 0
	else { throw ScenarioFailure.message("Cannot open nonlinked Plan session") }
	defer { Darwin.close(descriptor) }
	var info = stat()
	guard
		fstat(descriptor, &info) == 0,
		info.st_mode & S_IFMT == S_IFREG,
		info.st_size > 0,
		info.st_size <= 4_194_304
	else { throw ScenarioFailure.message("Invalid or oversized Plan session") }
	let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
	let bytes = try handle.read(upToCount: 65_537) ?? Data()
	guard
		let newline = bytes.firstIndex(of: 10),
		newline <= 65_536,
		let header = try JSONSerialization.jsonObject(with: bytes.prefix(upTo: newline))
			as? [String: Any],
		header["type"] as? String == "session",
		let cwd = header["cwd"] as? String,
		try ScenarioDirectoryIdentity.read(cwd) == ScenarioDirectoryIdentity.read(project.path)
	else { throw ScenarioFailure.message("Invalid or foreign Plan session header") }
}

struct PlanCleanupOutcome {
	let failures: [String]
	// Neither lifecycle acknowledgements nor Completed prove Pi/descendant quiescence.
	var cleanupConfirmed: Bool { false }
}

@MainActor func finishPlanLifecycle(
	attach: () async throws -> Void, stop: () async -> Bool,
	shutdown: () async -> Bool, completeSubmission: () async -> Void
) async -> PlanCleanupOutcome {
	var failures: [String] = []
	do { try await attach() } catch { failures.append("Scoped attach: \(error)") }
	if !(await stop()) { failures.append("Stop not acknowledged") }
	if !(await shutdown()) { failures.append("Shutdown/detach not acknowledged") }
	await completeSubmission()
	return PlanCleanupOutcome(failures: failures)
}

@MainActor func createCounterCollection(requirePlan: Bool) -> ScenarioCollection {
	ScenarioCollection(
		"agent-create", context: CreateCollection.init, setup: [],
		cases: [
			CreateCases.makeCase(
				requirePlan ? "create-counter-plan" : "create-counter",
				context: { CreateCounterContext(requirePlan: requirePlan) },
				setup: [
					CreateCases.step("validate private home and empty scoped library") {
						try await $0.validatePrivateLibrary()
					},
					CreateCases.step("assign unchanged Pebble Counter prompt and optional plan request") {
						try $0.assignPrompt()
					},
					CreateCases.step("resolve and preflight explicit SDK compiler") {
						try $0.preflightCompiler()
					},
				],
				behaviour: [
					CreateCases.step("submit Create request and establish generation deadline") {
						try $0.submit()
					},
					CreateCases.step("await bounded settlement and capture permitted ownership") {
						try await $0.awaitSettlement()
					},
					CreateCases.step("audit completed Create presentation and case-specific session policy") {
						try $0.auditCompletedSession()
					},
					CreateCases.step("audit implementation-time plan and final tasks when requested") {
						try $0.auditPlan()
					},
					CreateCases.step("audit latest authored passing counter Test before injection") {
						try await $0.auditAuthoredTests()
					},
					CreateCases.step("audit Preview archive and matched successful Build and Run") {
						try $0.auditPreviewAndBuildRun()
					},
					CreateCases.step("audit canonical naming and absence of native rename notification") {
						try $0.auditNaming()
					},
					CreateCases.step("refresh and audit canonical library title") {
						try await $0.auditLibraryTitle()
					},
					CreateCases.step("audit matched development bundle metadata") {
						try $0.auditDevelopmentMetadata()
					},
					CreateCases.step("capture exact development identity and verify private storage") {
						try await $0.captureDevelopmentAndStorage()
					},
					CreateCases.step("audit completed Test Preview Build Run activity") {
						try $0.auditActivity()
					},
					CreateCases.step("review bounded generated sources") { try $0.reviewSources() },
					CreateCases.step("compile and execute independent counter assertions") {
						try $0.verifyIndependentBehavior()
					},
					CreateCases.step("verify development remains alive after independent verification") {
						try $0.verifyDevelopmentLiveness()
					},
					CreateCases.step("verify production output remains absent") {
						try $0.verifyProductionOutputAbsent()
					},
					CreateCases.step("review last validated Preview through integrated Vision") {
						try await $0.reviewVision()
					},
					CreateCases.step("mark counter behavior passed") { try $0.markPassed() },
				])
		], cleanup: [CreateCollection.confirmationChain()])
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["AGENT_SCENARIO_LIVE"] == "1"))
@MainActor func agentCreateCounterScenario() async throws {
	try await runCreateScenario(
		caseName: "create-counter", testName: "agentCreateCounterScenario", includeVision: true,
		makeCollection: { createCounterCollection(requirePlan: false) })
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["AGENT_SCENARIO_LIVE"] == "1"))
@MainActor func agentCreatePlanScenario() async throws {
	try await runCreateScenario(
		caseName: "create-counter-plan", testName: "agentCreatePlanScenario", includeVision: true,
		makeCollection: { createCounterCollection(requirePlan: true) })
}
