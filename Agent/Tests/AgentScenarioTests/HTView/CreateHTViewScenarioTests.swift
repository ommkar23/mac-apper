// @frontmatter:start
// Exercises live HTView creation through native Agent XPC with authored tests, development launch, and independent WebKit verification.
// @frontmatter:end
import AgentMacosClient
import AgentMacosClientModel
import AgentScenarioSupport
import CoreFoundation
import Darwin
import Foundation
import Scenario
import Testing

let htViewCreatePrompt = """
	Build HTView, a human-usable native macOS viewer for one self-contained UTF-8 HTML file at a time, not a multi-file web project. Provide a normal local file picker and display the chosen document inside the generated ApplicationRoot using WebKit. Support inline CSS and inline JavaScript, including a scripted button that updates the document. Choose the visual design yourself.
	The user-visible app name must be HTView and the main window title must be HTView, including before opening a document. Keep this app branding when documents change. The HTML document title is not the main window title. Internal SwiftPM executable/target names such as ProductionApp may remain unchanged; they must not become user-visible app branding. Do not modify protected infrastructure.
	Show useful visible errors for missing, unreadable or invalid documents and browser load failures. Opening another valid document must clear the error and recover in the same root/model. Work fully offline. External assets, local servers, app-specific functional XPC and speculative extra features are outside this request.
	For independent verification, expose this small public @MainActor contract on ApplicationModel: openDocument(_ url: URL), documentURL: URL?, errorMessage: String?, and isLoading: Bool. The picker must use that same document action, and ApplicationRoot(model:) must render its result. Keep errorMessage nonempty on failure and nil on success. documentURL identifies the opened source file. isLoading becomes false when WebKit finishes or fails, not merely when the file was read. Keep generated navigation delegates, preprocessing and content rules in this path; propagate rule compilation failures as errors rather than bypassing them.
	Include a standalone example.html with inline styling and an interactive script. Resources may use SwiftPM .process or .copy in the standard AppModel/AppViews source directories, preserving Bundle.module. No additional external package dependencies are needed.
	Write meaningful Swift Testing tests for the actual local document action, observable errors and recovery. Test the real generated browser path too, including any content-rule compilation and load lifecycle; a separate bare WKWebView is not evidence for the app. Use Test, repair tool-level failures as needed within this request, then Build and Run when ready.
	"""

@MainActor private final class CreateHTViewContext: CaseContext {
	let adapter = AgentServiceXPCAdapter()
	let runtime: AgentXPCRuntime
	let workspace: WorkspaceSession
	var submission: Task<Void, Never>?
	var ownedProject: URL?
	var ownedPi: OwnedProcessIdentity?
	var runPassed = false

	init() {
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
		workspace.idea = htViewCreatePrompt
		// Recheck the selective snapshot at execution time; do not refresh authentication.
		_ = try CreateScenarioIsolation.credentialSnapshot(
			try #require(
				(JSONSerialization.jsonObject(
					with: Data(contentsOf: home.appendingPathComponent(".pi/agent/auth.json")))
					as? [String: [String: Any]])?["openai-codex"]))
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
		try verifyHTViewTesting(session: file, project: project, compiler: compiler)
		let evidence = try ScenarioToolEvidence(session: file)
		try #require(!evidence.calls.contains { $0.name.hasPrefix("mcp__parallel__") })
		let binary = try htViewLaunchBinary(evidence: evidence, project: project)
		let launched = try await ownedScaffoldProcess(binary)
		print("CREATE_RUN_IDENTITY: pid=\(launched.pid) start=\(launched.start) path=\(binary.path)")
		let store = home.appendingPathComponent(
			"Library/Application Support/MacApperGenerated/\(project.lastPathComponent)/CoreData/data.sqlite"
		)
		try #require(
			FileManager.default.fileExists(atPath: store.path),
			"Development production storage must be in the owned home")
		print("CREATE_ISOLATED_STORAGE: \(store.path)")
		for tool in ["test", "build", "run"] {
			try #require(workspace.state.liveDetails.contains { $0.hasPrefix("\(tool) · completed") })
		}
		try await verifyHTViewWebKit(project: project, compiler: compiler)
		print("CREATE_HTVIEW_WEBKIT: passed independent HTML/CSS/JavaScript verification")
		try #require(scaffoldProcessStart(launched.pid) == launched.start)
		try #require(
			scaffoldProcessPath(launched.pid).map { URL(fileURLWithPath: $0).resolvingSymlinksInPath() }
				== binary.resolvingSymlinksInPath(),
			"Matched Run development app not alive after independent verification")
		let output = project.deletingLastPathComponent().appendingPathComponent(
			"output/\(project.lastPathComponent)")
		print("CREATE_PRODUCTION_OUTPUT_EXISTS: \(FileManager.default.fileExists(atPath: output.path))")
		runPassed = true
	}

	func cleanup() async throws {
		// Never delete a partial-start project if its Pi identity was not captured.
		if ownedPi == nil, let file = workspace.sessionFile {
			let output = try command("/bin/ps", ["-ww", "-axo", "pid=,command="])
			let snapshot = try ScenarioProcessSnapshot.find(output, sessionPath: file.path)
			ownedPi = try OwnedProcessIdentity.capture(try #require(Int32(snapshot.pid)))
		}
		try #require(ownedProject == nil || ownedPi != nil, "Uncaptured Pi identity; retain host/home")
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
	try scaffoldCommand(
		URL(fileURLWithPath: executable), arguments, timeout: 10, logOutput: false)
}

@MainActor private final class CreateHTViewCollection: CollectionContext {}

@Test(.enabled(if: ProcessInfo.processInfo.environment["AGENT_SCENARIO_LIVE"] == "1"))
@MainActor func agentCreateHTViewScenario() async throws {
	let caseName = "create-htview"
	let testName = "agentCreateHTViewScenario"
	if ProcessInfo.processInfo.environment["AGENT_SCENARIO_TEST_HOST"] == "1" {
		_ = try ChatModelCases.serviceIdentifier()
		let collection = ScenarioCollection(
			"agent-create", context: CreateHTViewCollection.init,
			cases: [
				ScenarioCase(
					caseName, context: { _ in CreateHTViewContext() },
					steps: [
						Step("create, test, build, launch and independently verify HTView") { context in
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
				includeDevTools: true, includeVision: false, isolatedHome: home)
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

			], timeoutSeconds: 1320)
		print(result.output)
		cleanupConfirmed = result.output.contains(CreateScenarioIsolation.confirmation)
		passed = result.status == 0 && result.output.contains("Test \(testName)() passed")
		try #require(result.output.contains("Test \(testName)() started."))
		try #require(passed, "Packaged Create scenario failed")
	}
}

// Internal entry points allow coordinator-owned offline evidence regressions.
func verifyHTViewTesting(session: URL, project: URL, compiler: SDKCompiler) throws {
	let evidence = try ScenarioToolEvidence(session: session)
	let candidates = try evidence.testedSourcePaths(project: project)
	let finalRevision = try htViewFinalScopedRevision(evidence: evidence, project: project)
	try #require(
		evidence.calls.contains { call in
			guard
				call.succeeded,
				call.name == "test",
				call.started > finalRevision,
				call.typedResult?["status"] as? String == "passed",
				let code = call.typedResult?["exitCode"] as? NSNumber,
				CFGetTypeID(code) != CFBooleanGetTypeID()
			else { return false }
			return code.doubleValue == 0
		}, "Missing matched passing Test after final scoped app/test/manifest edits")
	try #require(
		!candidates.isEmpty, "Missing latest authored revision followed by a matched passing Test")
	let scratch = try ProjectTemporaryDirectory.appending(
		"mac-apper-htview-test-parse-\(UUID().uuidString)")
	try FileManager.default.createDirectory(
		at: scratch, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
	defer { try? FileManager.default.removeItem(at: scratch) }
	var opening = false, errors = false
	for relative in candidates {
		let source = try htViewScopedFile(project: project, relative: relative, maximum: 65_536)
		let parsed = try compiler.run(["-dump-parse", source.path], scratch: scratch)
		try #require(parsed.status == 0, "Authored HTView test could not be parsed")
		let lines = parsed.output.components(separatedBy: "\n")
		guard
			lines.contains(where: {
				$0.trimmingCharacters(in: .whitespaces).hasPrefix("(import_decl")
					&& $0.contains("module=\"Testing\"")
			})
		else { continue }
		for (index, line) in lines.enumerated()
		where line.trimmingCharacters(in: .whitespaces).hasPrefix("(func_decl") {
			let indent = line.prefix(while: { $0 == " " }).count
			let body = lines.dropFirst(index + 1).prefix {
				$0.isEmpty || $0.prefix(while: { $0 == " " }).count > indent
			}.map { $0.trimmingCharacters(in: .whitespaces) }
			guard
				body.contains(where: { $0.hasPrefix("(type_unqualified_ident id=\"Test\"") }),
				body.contains(where: {
					$0.hasPrefix("(macro_expansion_expr") && $0.contains("name=\"expect\"")
				})
			else { continue }
			// Expression identifiers exclude comments, test names and literal decoys.
			let references = body.filter {
				$0.hasPrefix("(unresolved_dot_expr") || $0.hasPrefix("(unresolved_decl_ref_expr")
			}.joined(separator: "\n").lowercased()
			opening =
				opening
				|| references.range(
					of: #"(?:field|name)="[^"]*(?:open|load|document|html)[^"]*""#,
					options: .regularExpression) != nil
			errors =
				errors
				|| references.range(
					of: #"(?:field|name)="[^"]*(?:error|fail|invalid|missing|unreadable)[^"]*""#,
					options: .regularExpression) != nil
		}
	}
	try #require(
		opening && errors,
		"Authored @Test/#expect bodies must exercise document opening and error state; untouched starter tests do not qualify"
	)
	print("CREATE_HTVIEW_TESTING: matched passing authored opening/error checks")
	// Structural evidence is not behavioral proof. WebKit verification runs independently.
}

private func htViewFinalScopedRevision(evidence: ScenarioToolEvidence, project: URL) throws -> Int {
	var revision = -1
	for call in evidence.calls where ["write", "edit"].contains(call.name) {
		let path = try #require(call.arguments["path"] as? String)
		let prefix = project.path + "/"
		let relative = path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : path
		guard
			["Sources/AppModel/", "Sources/AppViews/", "Tests/AppModelTests/"].contains(where: {
				relative.hasPrefix($0)
			})
				|| ["Package.swift", "app-manifest.json"].contains(relative)
		else { continue }
		let parts = relative.split(separator: "/", omittingEmptySubsequences: false)
		try #require(
			parts.allSatisfy {
				!$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains("\\") && !$0.contains("\0")
			})
		revision = max(revision, call.finished)
	}
	return revision
}

func htViewLaunchBinary(evidence: ScenarioToolEvidence, project: URL) throws -> URL {
	let manifestFile = try htViewScopedFile(
		project: project, relative: "app-manifest.json", maximum: 4096)
	let manifest = try #require(
		JSONSerialization.jsonObject(with: Data(contentsOf: manifestFile)) as? [String: Any])
	let target = try #require(manifest["executableTarget"] as? String)
	try #require(
		target.range(of: #"^[A-Za-z][A-Za-z0-9_]{0,63}$"#, options: .regularExpression) != nil)
	try #require(
		evidence.calls.contains {
			$0.succeeded && $0.name == "build" && $0.typedResult?["target"] as? String == target
				&& !($0.typedResult?["summary"] as? String ?? "").isEmpty
		}, "Missing matched successful Build")
	let run = try #require(
		evidence.calls.filter {
			$0.succeeded && $0.name == "run"
		}.max { $0.finished < $1.finished }, "Missing matched successful Run")
	let result = try #require(run.typedResult)
	try #require(result["target"] as? String == target)
	let relative = try #require(result["relativePath"] as? String)
	let parts = relative.split(separator: "/", omittingEmptySubsequences: false)
	try #require(
		parts.count == 4 && parts[0] == ".mac-apper" && parts[1] == "DevBuild"
			&& UUID(uuidString: String(parts[2])) != nil && parts[3] == "\(target).app")
	return try htViewScopedFile(
		project: project, relative: relative + "/Contents/MacOS/" + target, maximum: 134_217_728)
}

func htViewScopedFile(project: URL, relative: String, maximum: Int) throws -> URL {
	let parts = relative.split(separator: "/", omittingEmptySubsequences: false)
	try #require(
		!parts.isEmpty
			&& parts.allSatisfy {
				!$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains("\\") && !$0.contains("\0")
			})
	let root = try project.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
	try #require(root.isDirectory == true && root.isSymbolicLink != true)
	var file = project
	for part in parts {
		file.appendPathComponent(String(part))
		try #require(try file.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true)
	}
	let values = try file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
	try #require(values.isRegularFile == true && (values.fileSize ?? Int.max) <= maximum)
	return file
}
