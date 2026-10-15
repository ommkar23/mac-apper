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
			Build Pebble Counter, a small native macOS counter app. Use exactly Pebble Counter as its user-visible app name. Show a large count initially zero and buttons labeled Increment, Decrement, and Reset. Increment and Decrement should change the count by one, allow negative counts, and Reset should return it to zero. Keep it simple and fully offline.
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
		if requirePlan {
			try verifyCreatePlan(session: file, presentedTasks: workspace.state.tasks)
		}
		try await verifyCounterTesting(session: file, project: project)
		let preview = try verifyPreview(session: file, project: project)
		let evidence = try ScenarioToolEvidence(session: file)
		let name = try verifyCreateNaming(
			evidence: evidence, project: project, expectedName: "Pebble Counter")
		try verifyNamingPlist(project.appendingPathComponent("Info.plist"), expectedName: name)
		let journal = project.appendingPathComponent(".pi/agent-events/\(file.lastPathComponent)")
		try verifyNoNativeNamingNotification(journal: Data(contentsOf: journal))
		await workspace.refreshLibrary()
		let libraryEntry = try #require(workspace.library.first { $0.project == project })
		try #require(libraryEntry.title == name)
		try #require(workspace.state.liveDetails.contains { $0.hasPrefix("set_app_name · completed") })
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
		try #require(
			!FileManager.default.fileExists(atPath: output.path),
			"Metadata naming and normal development Run must not create a production package")
		try await verifyCounterVision(preview)
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

	func cleanup() async throws {
		if requirePlan {
			try await cleanupPlan()
			return
		}
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

// Scope-only evidence. Runtime/model/extension policy belongs to production, not this driver.
// Validation is point-in-time, not a filesystem lease against later replacement.
private func auditPlanSessionScope(file: URL, project: URL) throws {
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

private struct PlanCleanupOutcome {
	let failures: [String]
	// Neither lifecycle acknowledgements nor Completed prove Pi/descendant quiescence.
	var cleanupConfirmed: Bool { false }
}

@MainActor private func finishPlanLifecycle(
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

@Test func createPlanInterfacePolicyOffline() throws {
	let text = try String(contentsOfFile: #filePath, encoding: .utf8)
	let source = String(
		text.prefix(upTo: try #require(text.range(of: "private func command(")).lowerBound))
	#expect(source.contains("if !requirePlan, capturedArguments == nil"))
	#expect(source.contains("if requirePlan {\n\t\t\ttry await cleanupPlan()\n\t\t\treturn"))
	#expect(
		source.contains(
			"if requirePlan {\n\t\t\ttry auditPlanSessionScope(file: file, project: project)\n\t\t} else {"
		))
	let cleanup = String(
		source.suffix(from: try #require(source.range(of: "private func cleanupPlan()")).lowerBound))
	let planOnly = cleanup.prefix(
		upTo: try #require(cleanup.range(of: "\n\tfunc cleanup()")).lowerBound)
	for forbidden in [
		"/bin/ps", "ownedPi", ".reap(", "removeItem", "CreateScenarioIsolation.confirmation",
	] {
		#expect(!planOnly.contains(forbidden))
	}
}

@Test func createPlanInterfaceScopeOffline() throws {
	let root = try ProjectTemporaryDirectory.appending("plan-scope-offline-\(UUID().uuidString)")
	try FileManager.default.createDirectory(
		at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
	defer { try? FileManager.default.removeItem(at: root) }
	let project = root.appendingPathComponent("project")
	let sessions = project.appendingPathComponent(".pi/sessions")
	try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
	let file = sessions.appendingPathComponent("session.jsonl")
	func header(_ cwd: String) throws -> Data {
		var data = try JSONSerialization.data(withJSONObject: ["type": "session", "cwd": cwd])
		data.append(10)
		// Deliberately no model/thinking/extension metadata: this is scope, not runtime policy.
		return data
	}
	try header(project.path).write(to: file)
	try auditPlanSessionScope(file: file, project: project)
	try header(root.path).write(to: file)
	#expect(throws: (any Error).self) { try auditPlanSessionScope(file: file, project: project) }
	try header(project.path + "/../project").write(to: file)
	#expect(throws: (any Error).self) { try auditPlanSessionScope(file: file, project: project) }
	let link = root.appendingPathComponent("linked-project")
	try FileManager.default.createSymbolicLink(at: link, withDestinationURL: project)
	try header(link.path).write(to: file)
	#expect(throws: (any Error).self) { try auditPlanSessionScope(file: file, project: project) }
	try header(project.path).write(to: file)
	#expect(throws: (any Error).self) { try auditPlanSessionScope(file: file, project: link) }
	let linkedParent = project.appendingPathComponent("linked-sessions")
	try FileManager.default.createSymbolicLink(at: linkedParent, withDestinationURL: sessions)
	#expect(throws: (any Error).self) {
		try auditPlanSessionScope(
			file: linkedParent.appendingPathComponent(file.lastPathComponent), project: project)
	}
	let linkedFile = sessions.appendingPathComponent("linked.jsonl")
	try FileManager.default.createSymbolicLink(at: linkedFile, withDestinationURL: file)
	#expect(throws: (any Error).self) {
		try auditPlanSessionScope(file: linkedFile, project: project)
	}
	let outside = root.appendingPathComponent("outside.jsonl")
	try header(project.path).write(to: outside)
	#expect(throws: (any Error).self) { try auditPlanSessionScope(file: outside, project: project) }
	for invalid in ["{}\n", "{\"type\":\"message\",\"cwd\":\"/\"}\n", "not-json\n", "{}"] {
		try Data(invalid.utf8).write(to: file)
		#expect(throws: (any Error).self) { try auditPlanSessionScope(file: file, project: project) }
	}
	try Data(repeating: 120, count: 65_537).write(to: file)
	#expect(throws: (any Error).self) { try auditPlanSessionScope(file: file, project: project) }
	try Data(repeating: 120, count: 4_194_305).write(to: file)
	#expect(throws: (any Error).self) { try auditPlanSessionScope(file: file, project: project) }
}

@Test @MainActor func createPlanInterfaceCleanupOffline() async {
	var attempts: [String] = []
	let failed = await finishPlanLifecycle(
		attach: {
			attempts.append("attach"); throw ScenarioFailure.message("scope rejected")
		},
		stop: {
			attempts.append("stop"); return false
		},
		shutdown: {
			attempts.append("shutdown"); return false
		},
		completeSubmission: { attempts.append("submission") })
	#expect(attempts == ["attach", "stop", "shutdown", "submission"])
	#expect(failed.failures.count == 3)
	#expect(!failed.cleanupConfirmed)
	attempts = []
	let acknowledged = await finishPlanLifecycle(
		attach: { attempts.append("attach") },
		stop: {
			attempts.append("stop"); return true
		},
		shutdown: {
			attempts.append("shutdown"); return true
		},
		completeSubmission: { attempts.append("submission") })
	#expect(attempts == ["attach", "stop", "shutdown", "submission"])
	#expect(acknowledged.failures.isEmpty)
	#expect(!acknowledged.cleanupConfirmed, "Stop/detach acknowledgements do not prove quiescence")
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
