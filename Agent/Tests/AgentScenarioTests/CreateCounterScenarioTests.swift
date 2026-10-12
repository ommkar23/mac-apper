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

@MainActor private final class CreateCounterContext: CaseContext {
	let adapter = AgentServiceXPCAdapter()
	let runtime: AgentXPCRuntime
	let workspace: WorkspaceSession
	var submission: Task<Void, Never>?
	var ownedProject: URL?
	var ownedPi: OwnedProcessIdentity?
	var runPassed = false
	let requirePlan: Bool

	init(requirePlan: Bool = false) {
		self.requirePlan = requirePlan
		runtime = AgentXPCRuntime(transport: adapter)
		workspace = WorkspaceSession(
			runtime: runtime, workspaceStore: AgentXPCWorkspaceStore(transport: adapter))
		workspace.selectAgent("create")
	}

	func run() async throws {
		let home = try CreateScenarioIsolation.requireHome()
		await workspace.refreshLibrary()
		try #require(
			workspace.library.allSatisfy {
				$0.isChatOnly && $0.sessions.isEmpty
					&& $0.project.deletingLastPathComponent().resolvingSymlinksInPath()
						== home.appendingPathComponent(".mac-apper").resolvingSymlinksInPath()
			})
		workspace.idea = """
			Build a small native macOS counter app with a large count initially zero and buttons labeled Increment, Decrement, and Reset. Increment and Decrement should change the count by one, allow negative counts, and Reset should return it to zero. Keep it simple and fully offline.
			Launch the app when it is ready.
			"""
		if requirePlan {
			workspace.idea += """

				Keep an implementation plan using the plan tool: add tasks before implementing, mark a task in progress while working on it, and update tasks to completed as you finish. Complete all planned tasks before your final response.
				"""
		}
		let compiler = try SDKCompiler.resolve()
		submission = try SDKCompiler.beforeStartup(preflight: { try compiler.preflight() }) {
			Task { await workspace.submit() }
		}
		let deadline = ContinuousClock.now.advanced(by: .seconds(780))
		var capturedArguments: String?
		while workspace.busy || workspace.sessionFile == nil {
			try Task.checkCancellation()
			if let project = workspace.project {
				if ownedProject == nil {
					let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
						".mac-apper")
					try #require(
						project.deletingLastPathComponent().resolvingSymlinksInPath()
							== root.resolvingSymlinksInPath())
					try #require(UUID(uuidString: project.lastPathComponent) != nil)
					ownedProject = project
					print("CREATE_PROJECT: \(project.path)")
				}
				if capturedArguments == nil, let file = workspace.sessionFile {
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
			try #require(
				ContinuousClock.now < deadline, "Create deadline exceeded: \(workspace.state.status)")
			try #require(
				workspace.busy || workspace.state.status != "Failed", "Create failed: \(workspace.activity)"
			)
			try await Task.sleep(for: .milliseconds(100))
		}
		let project = try #require(ownedProject)
		let file = try #require(workspace.sessionFile)
		try #require(
			workspace.state.status == "Completed", "\(workspace.state.status): \(workspace.activity)")
		#expect(!workspace.isChatOnly && workspace.selectedAgentID == "create")
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
		#expect(arguments.contains("AgentExtensions/parallel-codemode.ts"))
		#expect(!arguments.contains("Web.app"))
		#expect(arguments.contains("DevTools.app/Contents/Resources/PiExtension/Extension.ts"))
		print("CREATE_REPLY: \(workspace.messages.last(where: { !$0.isUser })?.text ?? "")")
		print("CREATE_ACTIVITY: \(workspace.state.liveDetails.joined(separator: "\n"))")
		if requirePlan {
			try verifyCreatePlan(session: file, presentedTasks: workspace.state.tasks)
		}
		try await verifyCounterTesting(session: file, project: project)
		let preview = try verifyPreview(session: file, project: project)
		let evidence = try ScenarioToolEvidence(session: file)
		let run = try #require(
			evidence.calls.filter { $0.name == "run" && $0.succeeded }.max(by: {
				$0.finished < $1.finished
			}))
		let result = try #require(run.typedResult)
		let relative = try #require(result["relativePath"] as? String)
		let target = try #require(result["target"] as? String)
		let binary = project.appendingPathComponent(relative + "/Contents/MacOS/" + target)
		let launched = try await ownedScaffoldProcess(binary)
		print("CREATE_RUN_IDENTITY: pid=\(launched.pid) start=\(launched.start) path=\(binary.path)")
		let store = home.appendingPathComponent(
			"Library/Application Support/MacApperGenerated/\(project.lastPathComponent)/CoreData/data.sqlite"
		)
		try #require(
			FileManager.default.fileExists(atPath: store.path),
			"Development production storage must be in the owned home")
		print("CREATE_ISOLATED_STORAGE: \(store.path)")
		for tool in ["test", "preview", "build", "run"] {
			#expect(
				workspace.state.liveDetails.contains(where: { $0.hasPrefix("\(tool) · completed") }),
				"Missing completed \(tool) activity")
		}
		for path in [
			"Package.swift", "app-manifest.json", "Sources/AppModel/ApplicationModel.swift",
			"Sources/AppViews/ApplicationRoot.swift", "Tests/AppModelTests/ApplicationTests.swift",
		] {
			let text = try String(contentsOf: project.appendingPathComponent(path), encoding: .utf8)
			try #require(text.utf8.count < 100_000)
			print("CREATE_SOURCE \(path):\n\(text)")
		}
		// Independent behavioral assertions, not merely the generated agent's own tests.
		try verifyIndependentCounter(project: project, compiler: compiler)
		print("CREATE_MODEL_TESTS: passed (generated tests plus independent counter assertions)")
		try #require(scaffoldProcessStart(launched.pid) == launched.start)
		try #require(
			scaffoldProcessPath(launched.pid).map { URL(fileURLWithPath: $0).resolvingSymlinksInPath() }
				== binary.resolvingSymlinksInPath(),
			"Matched Run development app not alive after independent verification")
		let output = project.deletingLastPathComponent().appendingPathComponent(
			"output/\(project.lastPathComponent)")
		print("CREATE_PRODUCTION_OUTPUT_EXISTS: \(FileManager.default.fileExists(atPath: output.path))")
		try await verifyCounterVision(preview)
		runPassed = true
	}

	func cleanup() async throws {
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
		print(CreateScenarioIsolation.confirmation)
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

@MainActor private final class CreateCollection: CollectionContext {}

@Test(.enabled(if: ProcessInfo.processInfo.environment["AGENT_SCENARIO_LIVE"] == "1"))
@MainActor func agentCreateCounterScenario() async throws {
	try await runCreateCounterScenario(requirePlan: false)
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["AGENT_SCENARIO_LIVE"] == "1"))
@MainActor func agentCreatePlanScenario() async throws {
	try await runCreateCounterScenario(requirePlan: true)
}

@MainActor private func runCreateCounterScenario(requirePlan: Bool) async throws {
	let caseName = requirePlan ? "create-counter-plan" : "create-counter"
	let testName = requirePlan ? "agentCreatePlanScenario" : "agentCreateCounterScenario"
	if ProcessInfo.processInfo.environment["AGENT_SCENARIO_TEST_HOST"] == "1" {
		_ = try ChatModelCases.serviceIdentifier()
		let collection = ScenarioCollection(
			"agent-create", context: CreateCollection.init,
			cases: [
				ScenarioCase(
					caseName, context: { _ in CreateCounterContext(requirePlan: requirePlan) },
					steps: [
						Step("create, test, preview, build, launch and visually evaluate counter") { context in
							try await withThrowingTaskGroup(of: Void.self) { group in
								group.addTask { try await context.run() }
								group.addTask {
									try await Task.sleep(for: .seconds(1020))
									throw ScenarioFailure.message("Create execution deadline exceeded")
								}
								defer { group.cancelAll() }
								try await group.next()
							}
						}
					], teardown: { try await $0.cleanup() })
			])
		try await ScenarioRegistry([collection]).runCase(caseName)
	} else {
		let home = try CreateScenarioIsolation.prepareHome()
		var cleanupConfirmed = true  // No inner processes exist until runTest starts.
		var passed = false
		let host: PackagedTestHost
		do {
			host = try AgentChatScenarioInputs.prepareHost(
				includeDevTools: true, includeVision: true, isolatedHome: home)
		} catch {
			try home.remove(cleanupConfirmed: true)  // No test/Pi was started.
			throw error
		}
		defer {
			do {
				let removed = try home.finishHost(
					cleanupConfirmed: cleanupConfirmed,
					removeFixtures: passed
						&& ProcessInfo.processInfo.environment["AGENT_CREATE_KEEP_PROJECT"] != "1",
					stopServices: {
						try stopScaffoldService(
							host.app, relative: "AgentXPCService.xpc/Contents/MacOS/AgentApplication")
						try stopScaffoldService(
							host.app?.appendingPathComponent("Contents/Applications/DevTools.app"),
							relative: "DevToolsApplication.xpc/Contents/MacOS/DevToolsApplication")
					}, removeHost: { try host.remove() })
				if removed {
					print("CREATE_HOST_HOME_CLEANUP: removed after confirmed process reaping")
				} else {
					print(
						"CREATE_RETAINED_HOST_HOME: host=\(host.app?.path ?? "unavailable") home=\(home.directory.path)"
					)
				}
			} catch {
				Issue.record("Owned Create cleanup failed; retain signed host/home: \(error)")
				print(
					"CREATE_RETAINED_HOST_HOME: host=\(host.app?.path ?? "unavailable") home=\(home.directory.path)"
				)
			}
		}
		let app = try #require(host.app)
		print("CREATE_ISOLATED_HOST_HOME: host=\(app.path) home=\(home.directory.path)")
		_ = try CreateScenarioIsolation.credentialSnapshot(
			try #require(
				(JSONSerialization.jsonObject(
					with: Data(contentsOf: home.directory.appendingPathComponent(".pi/agent/auth.json")))
					as? [String: [String: Any]])?["openai-codex"]))
		cleanupConfirmed = false
		let result = try host.runTest(
			filter: "^AgentScenarioTests\\.\(testName)",
			environment: [
				"AGENT_SCENARIO_TEST_HOST": "1",
				"AGENT_CREATE_HOME": home.directory.path,
				"HOME": home.directory.path, "CFFIXED_USER_HOME": home.directory.path,
				"AGENT_SCENARIO_VISION_CLI": app.appendingPathComponent(
					"Contents/Resources/VisionCLI/vision-cli"
				).path,
				"AGENT_VISION_ENV_FILE": try counterVisionEnvFile().path,
			], timeoutSeconds: 1320)
		print(result.output)
		cleanupConfirmed = result.output.contains(CreateScenarioIsolation.confirmation)
		passed = result.status == 0 && result.output.contains("Test \(testName)() passed")
		try #require(result.output.contains("Test \(testName)() started."))
		try #require(passed, "Packaged Create scenario failed")
	}
}
