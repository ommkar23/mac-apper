// @frontmatter:start
// Verifies fresh v9 scaffold naming, library metadata, signed DevTools Test/Preview/Build/Run and isolated persistence without models.
// @frontmatter:end
import AgentMacosClient
import AgentMacosClientModel
import CryptoKit
import Darwin
import Foundation
import ImageIO
import Scenario
import Testing

@Test(.enabled(if: ProcessInfo.processInfo.environment["AGENT_SCAFFOLD_DEVTOOLS_SCENARIO"] == "1"))
@MainActor func agentScaffoldDevToolsScenario() async throws {
	let environment = ProcessInfo.processInfo.environment
	if environment["AGENT_SCAFFOLD_DEVTOOLS_HOST"] == "1" {
		try await runScaffoldDevToolsScenario()
	} else {
		let home = try ProjectTemporaryDirectory.appending(
			"mac-apper-coredata-host-\(UUID().uuidString)")
		try FileManager.default.createDirectory(
			at: home.appendingPathComponent(".mac-apper"), withIntermediateDirectories: true,
			attributes: [.posixPermissions: 0o700])
		// Only the compiler installation is linked into the private home; stores/caches stay isolated.
		let installed = try SwiftToolchain.executable("swift").deletingLastPathComponent()
			.deletingLastPathComponent().deletingLastPathComponent()
		let toolchains = home.appendingPathComponent("Library/Developer/Toolchains")
		try FileManager.default.createDirectory(at: toolchains, withIntermediateDirectories: true)
		try FileManager.default.createSymbolicLink(
			at: toolchains.appendingPathComponent(installed.lastPathComponent),
			withDestinationURL: installed)
		var completed = false
		var serviceCleaned = false
		var innerCleanupConfirmed = false
		defer {
			if completed && serviceCleaned {
				try? FileManager.default.removeItem(at: home)
			} else {
				print("CORE_DATA_RETAINED_HOME: \(home.path)")
			}
		}
		let host = try AgentResourceScenarioInputs.prepareHost(home: home)
		defer {
			do {
				try #require(innerCleanupConfirmed, "Unconfirmed inner cleanup; retain Agent host/home")
				try stopScaffoldService(
					host.app, relative: "AgentXPCService.xpc/Contents/MacOS/AgentApplication")
				try host.remove()
				serviceCleaned = true
			} catch {
				Issue.record("Owned Agent service cleanup failed: \(error)")
			}
		}
		print("CORE_DATA_AGENT_SIGNED_HOST: \(try #require(host.app).path)")
		let result = try host.runTest(
			filter: "^AgentScenarioTests.agentScaffoldDevToolsScenario",
			environment: [
				"AGENT_SCAFFOLD_DEVTOOLS_HOST": "1", "AGENT_RESOURCE_HOME": home.path,
				"HOME": home.path, "CFFIXED_USER_HOME": home.path,
			],
			timeoutSeconds: 1200)
		print(result.output)
		innerCleanupConfirmed = result.output.contains("CORE_DATA_INNER_CLEANUP_CONFIRMED")
		try #require(innerCleanupConfirmed)
		try #require(result.output.contains("Test agentScaffoldDevToolsScenario() started."))
		try #require(result.status == 0, "Offline packaged scaffold integration failed")
		completed = true
	}
}

@MainActor private func runScaffoldDevToolsScenario() async throws {
	let home = URL(
		fileURLWithPath: try #require(ProcessInfo.processInfo.environment["AGENT_RESOURCE_HOME"]))
	let adapter = AgentServiceXPCAdapter()
	let store = AgentXPCWorkspaceStore(transport: adapter)
	let model = WorkspaceSession(runtime: AgentXPCRuntime(transport: adapter), workspaceStore: store)
	await model.refreshLibrary()
	try #require(model.library.allSatisfy { $0.isChatOnly && $0.sessions.isEmpty })
	let prepared = try await store.prepareCreateProject(
		request: "Offline synthetic Core Data integration")
	let root = prepared.project
	let agentBinary = Bundle.main.bundleURL.appendingPathComponent(
		"Contents/XPCServices/AgentXPCService.xpc/Contents/MacOS/AgentApplication")
	let agentProcess = try await ownedScaffoldProcess(agentBinary)
	print(
		"CORE_DATA_AGENT_SERVICE_IDENTITY: \(agentProcess.pid) \(agentProcess.start) \(agentBinary.path)"
	)
	try #require(
		root.deletingLastPathComponent().resolvingSymlinksInPath().path
			== home.appendingPathComponent(".mac-apper").resolvingSymlinksInPath().path)
	let id = try #require(UUID(uuidString: root.lastPathComponent))
	await model.openProject(root)
	try #require(model.project == root && !model.connected && model.sessions.isEmpty)
	try #require(!FileManager.default.fileExists(atPath: prepared.sessionFile.path))
	try #require(
		String(contentsOf: root.appendingPathComponent("Scaffold.version"), encoding: .utf8) == "9")
	let original = try scaffoldSourceSnapshot(root)
	let persistence = try #require(original["Sources/AppModel/Persistence.swift"])
	try #require(String(decoding: persistence, as: UTF8.self).contains("schema.entities = []"))
	print(
		"CORE_DATA_FRESH_SCAFFOLD: \(root.path); starter schema empty, transient UI is not user data")
	try ScaffoldDevToolsFixture.install(in: root)
	let modified = try scaffoldSourceSnapshot(root)
	let editable = Set([
		"Package.swift", "Sources/AppModel/Persistence.swift",
		"Sources/AppModel/ApplicationModel.swift",
	])
	for (path, bytes) in original where !editable.contains(path) {
		try #require(modified[path] == bytes, "Protected/original source changed: \(path)")
	}
	let beforeNaming = try scaffoldNamingPlist(root, relative: "Info.plist")
	let host = try scaffoldDevToolsHost(home: home)
	var requestsConfirmed = true
	var childConfirmed = true
	var service: OwnedProcessIdentity?
	var cleanupAttempted = false
	func captureService() throws -> OwnedProcessIdentity {
		let binary = try #require(host.app).appendingPathComponent(
			"Contents/XPCServices/DevToolsApplication.xpc/Contents/MacOS/DevToolsApplication")
		let current = try OwnedExecutableProcess.capture(executable: binary)
		if let service {
			return try scaffoldReattributeService(service, capture: { current })
		}
		service = current
		print("CORE_DATA_DEVTOOLS_SERVICE_IDENTITY: \(current.pid) \(current.start) \(current.path)")
		return current
	}
	func finishHost() throws {
		cleanupAttempted = true
		try #require(requestsConfirmed && childConfirmed, "Uncertain request/child; retain fixtures")
		if service != nil {
			// A stale cached PID reaching ESRCH cannot exclude a live replacement in this host.
			let attributed = try captureService()
			try attributed.reap()
			try attributed.requireReaped()
			print(
				"CORE_DATA_DEVTOOLS_SERVICE_REAPED: \(attributed.pid) \(attributed.start) \(attributed.path)"
			)
		}
		try host.remove()
		print("CORE_DATA_INNER_CLEANUP_CONFIRMED")
	}
	defer {
		if !cleanupAttempted {
			do { try finishHost() } catch {
				Issue.record("Owned DevTools cleanup unconfirmed; retain host/home: \(error)")
			}
		}
	}
	let session = UUID()
	func request(_ command: String, payload: [String: Any]) throws -> [String: Any] {
		requestsConfirmed = false
		if service != nil { _ = try captureService() }
		let result = try host.request(command, payload: payload, projectID: id, sessionID: session)
		// Confirm only a matched successful envelope from the same exact-host service generation.
		_ = try captureService()
		requestsConfirmed = true
		return result
	}
	print(
		"CORE_DATA_DEVTOOLS_SIGNED_HOST: \(try #require(host.app).path); production DevToolsTerminalClient/DevToolsApplication"
	)
	try scaffoldNamingHasNoBuildOutput(root: root, home: home)
	let named = try request(
		"set_app_name",
		payload: ["projectRoot": root.path, "name": "  Pebble / Counter: .app.APP  "])
	let canonical = try #require(named["name"] as? String)
	try #require(canonical == "Pebble Counter")
	try #require(named["summary"] as? String == "App name set to Pebble Counter.")
	let afterNaming = try scaffoldNamingPlist(root, relative: "Info.plist")
	var expected = beforeNaming
	expected["CFBundleDisplayName"] = canonical
	expected["CFBundleName"] = canonical
	try #require(NSDictionary(dictionary: afterNaming).isEqual(to: expected))
	try #require(try scaffoldSourceSnapshot(root) == modified)
	try scaffoldNamingHasNoBuildOutput(root: root, home: home)
	await model.refreshLibrary()
	let groups = model.library.filter { $0.project == root && !$0.isChatOnly }
	try #require(groups.count == 1 && groups.first?.title == canonical && groups.first?.app == nil)
	print("CORE_DATA_NAMING: matched signed result/project/library = \(canonical); metadata only")
	let tested = try request("test", payload: ["projectRoot": root.path])
	print("CORE_DATA_TEST_RESULT: \(tested)")
	try #require(tested["status"] as? String == "passed" && tested["exitCode"] as? Int == 0)
	let diagnostics = try #require(tested["diagnostics"] as? String)
	try #require(diagnostics.utf8.count <= 4096)
	try #require(diagnostics.contains("packagedTypedCoreDataSaveRollbackReopen() passed"))
	let preview = try request(
		"preview",
		payload: [
			"projectRoot": root.path, "viewPath": "Sources/AppViews/PersistencePreview.swift",
			"screenSize": ["width": 320, "height": 240],
		])
	try validateScaffoldPreview(preview, root: root, home: home, id: id, session: session)
	let built = try request("build", payload: ["projectRoot": root.path])
	try #require(built["target"] as? String == "ProductionApp")
	print("CORE_DATA_BUILD_RESULT: \(built)")
	try scaffoldFreshProcesses(root: root, home: home)
	childConfirmed = false
	let launched = try request("run", payload: ["projectRoot": root.path])
	try #require(launched["target"] as? String == "ProductionApp")
	let relative = try #require(launched["relativePath"] as? String)
	try #require(
		relative.range(
			of: #"^\.mac-apper/DevBuild/[0-9a-f-]{36}/ProductionApp\.app$"#, options: .regularExpression)
			!= nil)
	let binary = root.appendingPathComponent(relative + "/Contents/MacOS/ProductionApp")
	let process = try await ownedScaffoldProcess(binary)
	print("CORE_DATA_RUN_IDENTITY: \(process.pid) \(process.start) \(binary.path)")
	_ = try captureService()
	try await stopScaffoldProcess(process, binary: binary)
	childConfirmed = true
	let staged = try scaffoldNamingPlist(root, relative: relative + "/Contents/Info.plist")
	try #require(staged["CFBundleDisplayName"] as? String == canonical)
	try #require(staged["CFBundleName"] as? String == canonical)
	try #require(staged["CFBundleExecutable"] as? String == "ProductionApp")
	try #require(staged["CFBundleVersion"] as? String == String(relative.split(separator: "/")[2]))
	try #require(staged["CFBundleShortVersionString"] as? String == "0")
	try #require(
		staged["CFBundleIdentifier"] as? String == "com.macapper.dev.\(root.lastPathComponent)")
	try #require(
		try scaffoldNamingPlist(root, relative: "Info.plist") as NSDictionary == afterNaming
			as NSDictionary)
	print(
		"CORE_DATA_NAMING_STAGE: \(relative)/Contents/Info.plist = \(canonical); no rendered title/menu observation"
	)
	try #require(try scaffoldSourceSnapshot(root) == modified)
	for path in [".mac-apper/TestBuild", ".mac-apper/PreviewBuild"] {
		let url = root.appendingPathComponent(path)
		if FileManager.default.fileExists(atPath: url.path) {
			try #require(FileManager.default.contentsOfDirectory(atPath: url.path).isEmpty)
		}
	}
	try #require(!FileManager.default.fileExists(atPath: root.appendingPathComponent(".build").path))
	try finishHost()
	try FileManager.default.removeItem(at: root)
	print(
		"CORE_DATA_CLEANUP: owned development PID exited; sources preserved, Test/Preview scratch empty, project removed"
	)
}

@MainActor private func scaffoldDevToolsHost(home: URL) throws -> PackagedXPCHost {
	let package = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
		.deletingLastPathComponent()
		.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(
			"apps/built-in/dev-tools")
	let products =
		ProcessInfo.processInfo.environment["DEV_TOOLS_SCENARIO_PRODUCTS"].map {
			URL(fileURLWithPath: $0)
		}
		?? package.appendingPathComponent(".build/debug")
	return try PackagedTestHost.withInputDirectory { inputs in
		let plist = package.appendingPathComponent("Resources/DevToolsXPCService-Info.plist")
		var info = try #require(
			PropertyListSerialization.propertyList(from: Data(contentsOf: plist), format: nil)
				as? [String: Any])
		var xpc = try #require(info["XPCService"] as? [String: Any])
		xpc["EnvironmentVariables"] = ["HOME": home.path, "CFFIXED_USER_HOME": home.path]
		info["XPCService"] = xpc
		let scoped = inputs.appendingPathComponent("DevTools.plist")
		try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(
			to: scoped)
		let host = PackagedXPCHost(
			try XPCHostDefinition(
				appName: "CoreDataDevTools",
				clientExecutable: products.appendingPathComponent("DevToolsTerminalClient"),
				serviceExecutable: products.appendingPathComponent("DevToolsApplication"),
				appPlist: package.appendingPathComponent("Resources/Info.plist"), servicePlist: scoped,
				serviceResources: [
					TestHostResource(
						source: products.appendingPathComponent("DevTools_DevToolsApplication.bundle"),
						relativePath: "DevTools_DevToolsApplication.bundle")
				], clientEnvironment: ["HOME": home.path, "CFFIXED_USER_HOME": home.path]))
		// Input directory lifetime ends here; preparation consumes its scoped plist synchronously.
		try host.prepare()
		return host
	}
}

// Discovery-free seam: production callers supply exact-host live service capture.
private func scaffoldReattributeService(
	_ cached: OwnedProcessIdentity, capture: () throws -> OwnedProcessIdentity
) throws -> OwnedProcessIdentity {
	let current = try capture()
	guard
		current.pid == cached.pid,
		current.path == cached.path,
		current.start == cached.start
	else { throw ScenarioFailure.message("unexpected scaffold service generation; retain fixtures") }
	return current
}

@Test func scaffoldServiceGenerationOffline() throws {
	let cached = OwnedProcessIdentity(pid: 123, start: 456, path: "/owned/DevToolsApplication")
	for replacement in [
		OwnedProcessIdentity(pid: 124, start: cached.start, path: cached.path),
		OwnedProcessIdentity(pid: cached.pid, start: 457, path: cached.path),
		OwnedProcessIdentity(
			pid: cached.pid, start: cached.start, path: "/foreign/DevToolsApplication"),
	] {
		var cleanupContinued = false
		#expect(throws: ScenarioFailure.self) {
			_ = try scaffoldReattributeService(cached, capture: { replacement })
			cleanupContinued = true
		}
		#expect(!cleanupContinued, "Replacement cannot reach host removal or inner cleanup marker")
	}
	let unchanged = try scaffoldReattributeService(cached, capture: { cached })
	#expect(
		unchanged.pid == cached.pid && unchanged.path == cached.path && unchanged.start == cached.start)
	#expect(throws: ScenarioFailure.self) {
		try scaffoldReattributeService(
			cached, capture: { throw ScenarioFailure.message("uncertain capture") })
	}
	// ESRCH for an obsolete PID is not proof that this host has no replacement generation.
	let stale = OwnedProcessIdentity(pid: Int32.max, start: 1, path: cached.path)
	try stale.requireReaped()
	var staleCleanupContinued = false
	#expect(throws: ScenarioFailure.self) {
		_ = try scaffoldReattributeService(stale, capture: { cached })
		staleCleanupContinued = true
	}
	#expect(!staleCleanupContinued, "Cached ESRCH cannot authorize fixture removal")
}

private let scaffoldNamingLeafFlags = O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK

@Test func scaffoldNamingFIFOOffline() throws {
	// Guard before touching the FIFO so the red regression cannot itself block indefinitely.
	try #require(scaffoldNamingLeafFlags & O_NONBLOCK != 0)
	let root = try ProjectTemporaryDirectory.appending("scaffold-naming-fifo-\(UUID().uuidString)")
	try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
	defer { try? FileManager.default.removeItem(at: root) }
	try #require(mkfifo(root.appendingPathComponent("Info.plist").path, 0o600) == 0)
	let start = ContinuousClock.now
	withKnownIssue { _ = try? scaffoldNamingPlist(root, relative: "Info.plist") }
	#expect(start.duration(to: .now) < .seconds(2))
}

// Local deterministic reads deliberately do not depend on the shared Create naming-evidence API.
private func scaffoldNamingPlist(_ root: URL, relative: String) throws -> [String: Any] {
	let components = relative.split(separator: "/", omittingEmptySubsequences: false)
	try #require(components.allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." })
	try #require(!relative.contains("\\") && relative.utf8.count <= 1024)
	var descriptor = open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
	try #require(descriptor >= 0)
	defer { close(descriptor) }
	for (index, component) in components.enumerated() {
		let flags =
			index == components.count - 1
			? scaffoldNamingLeafFlags : O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_DIRECTORY
		let next = openat(descriptor, String(component), flags)
		try #require(next >= 0, "Missing/linked naming metadata: \(relative)")
		close(descriptor)
		descriptor = next
	}
	var info = stat()
	try #require(fstat(descriptor, &info) == 0 && info.st_mode & S_IFMT == S_IFREG)
	try #require(info.st_size > 0 && info.st_size <= 16384)
	let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
	var bytes = Data()
	while let chunk = try handle.read(upToCount: 16385 - bytes.count), !chunk.isEmpty {
		bytes.append(chunk)
		try #require(bytes.count <= 16384)
	}
	return try #require(
		PropertyListSerialization.propertyList(from: bytes, format: nil) as? [String: Any])
}

private func scaffoldNamingHasNoBuildOutput(root: URL, home: URL) throws {
	for path in [
		".build", ".mac-apper/Build", ".mac-apper/DevBuild", ".mac-apper/TestBuild",
		".mac-apper/PreviewBuild",
	] {
		try #require(!FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path))
	}
	try #require(
		FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("dist").path)
			.isEmpty)
	try #require(
		!FileManager.default.fileExists(atPath: home.appendingPathComponent(".mac-apper/output").path))
}

@Test func scaffoldNamingLocalReadsOffline() throws {
	let root = try ProjectTemporaryDirectory.appending("scaffold-naming-reads-\(UUID().uuidString)")
	try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
	defer { try? FileManager.default.removeItem(at: root) }
	let contents = root.appendingPathComponent("Stage.app/Contents")
	try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
	let plist = contents.appendingPathComponent("Info.plist")
	try PropertyListSerialization.data(
		fromPropertyList: ["CFBundleName": "Pebble Counter", "Unrelated": ["keep": 7]],
		format: .binary, options: 0
	).write(to: plist)
	let read = try scaffoldNamingPlist(root, relative: "Stage.app/Contents/Info.plist")
	#expect(read["CFBundleName"] as? String == "Pebble Counter")
	#expect((read["Unrelated"] as? [String: Int])?["keep"] == 7)
	try FileManager.default.createSymbolicLink(
		at: root.appendingPathComponent("Linked.app"),
		withDestinationURL: root.appendingPathComponent("Stage.app"))
	// Validation failures are expected issues from #require, not successful metadata reads.
	withKnownIssue { _ = try? scaffoldNamingPlist(root, relative: "Linked.app/Contents/Info.plist") }
	withKnownIssue {
		_ = try? scaffoldNamingPlist(root, relative: "../Stage.app/Contents/Info.plist")
	}
	try Data(repeating: 32, count: 16385).write(to: plist)
	withKnownIssue { _ = try? scaffoldNamingPlist(root, relative: "Stage.app/Contents/Info.plist") }
}

private func scaffoldSourceSnapshot(_ root: URL) throws -> [String: Data] {
	var result: [String: Data] = [:]
	for path in [
		"Package.swift", "Package.resolved", "Scaffold.version", "app-manifest.json", ".gitignore",
	] {
		result[path] = try Data(contentsOf: root.appendingPathComponent(path))
	}
	for directory in ["Sources", "Tests"] {
		let files = try #require(
			FileManager.default.enumerator(
				at: root.appendingPathComponent(directory),
				includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey]))
		for case let url as URL in files {
			let values = try url.resourceValues(forKeys: [
				.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey,
			])
			try #require(values.isSymbolicLink != true)
			if values.isRegularFile == true {
				try #require((values.fileSize ?? Int.max) <= 65536 && result.count < 128)
				let relative = url.resolvingSymlinksInPath().path.dropFirst(
					root.resolvingSymlinksInPath().path.count + 1)
				result[String(relative)] = try Data(contentsOf: url)
			}
		}
	}
	return result
}

private func validateScaffoldPreview(
	_ response: [String: Any], root: URL, home: URL, id: UUID, session: UUID
) throws {
	try #require(response["status"] as? String == "rendered", "\(response)")
	try #require(response["width"] as? Int == 320 && response["height"] as? Int == 240)
	let artifact = try #require(response["artifact"] as? [String: Any])
	try #require(artifact["kind"] as? String == "png")
	let relative = try #require(artifact["relativePath"] as? String)
	try #require(
		relative.range(
			of: #"^\.mac-apper/Artifacts/[0-9a-f-]{36}/render\.png$"#, options: .regularExpression) != nil
	)
	let url = root.appendingPathComponent(relative)
	let values = try url.resourceValues(forKeys: [
		.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey,
	])
	try #require(
		values.isRegularFile == true && values.isSymbolicLink != true
			&& (values.fileSize ?? Int.max) <= 2097152)
	let bytes = try Data(contentsOf: url)
	try #require(bytes.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]))
	let source = try #require(CGImageSourceCreateWithData(bytes as CFData, nil))
	try #require(CGImageSourceGetType(source) as String? == "public.png")
	let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
	try #require(image.width == 320 && image.height == 240)
	var pixel = [UInt8](repeating: 0, count: 4)
	try pixel.withUnsafeMutableBytes { buffer in
		let context = try #require(
			CGContext(
				data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
				bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
				bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
		context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
	}
	try #require(
		pixel[0] > 200 && pixel[2] < 80,
		"Injected saved memory model state must render red, not default blue")
	let review = URL(fileURLWithPath: try #require(artifact["reviewPath"] as? String))
	try #require(
		review.deletingLastPathComponent().resolvingSymlinksInPath().path
			== home.appendingPathComponent(
				".mac-apper/previews/\(id.uuidString.lowercased())/\(session.uuidString.lowercased())"
			).resolvingSymlinksInPath().path)
	try #require(Data(contentsOf: review) == bytes)
	let exported = try ProjectTemporaryDirectory.appending(
		"mac-apper-coredata-task5-\(id.uuidString.lowercased()).png")
	try bytes.write(to: exported, options: .withoutOverwriting)
	print(
		"CORE_DATA_PREVIEW: 320x240 injected red; sha256=\(SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()) export=\(exported.path)"
	)
}

@MainActor private func scaffoldFreshProcesses(root: URL, home: URL) throws {
	let scratch = home.appendingPathComponent("probe-build")
	try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: false)
	let swift = try SwiftToolchain.executable("swift")
	func call(_ executable: URL, _ arguments: [String], timeout: Int) throws -> String {
		try scaffoldCommand(
			executable, arguments,
			environment: [
				"HOME": home.path, "CFFIXED_USER_HOME": home.path,
				"SWIFT_EXEC": try SwiftToolchain.executable("swiftc").path,
			], timeout: timeout)
	}
	let version = try call(swift, ["--version"], timeout: 15)
	try #require(version.contains("Swift version 6.4") && version.contains("swift-6.4-RELEASE"))
	_ = try call(
		swift,
		[
			"build", "--package-path", root.path, "--scratch-path", scratch.path,
			"--product", "PersistenceProbe", "-j", "2",
		], timeout: 300)
	let bin = try call(
		swift,
		[
			"build", "--package-path", root.path, "--scratch-path", scratch.path,
			"--show-bin-path",
		], timeout: 60
	).trimmingCharacters(in: .whitespacesAndNewlines)
	let executable = URL(fileURLWithPath: bin).appendingPathComponent("PersistenceProbe")
	for mode in ["write", "check", "delete", "absent"] {
		let output = try call(
			executable, [mode, home.appendingPathComponent("probe-home").path], timeout: 30)
		try #require(output.contains("PACKAGED_FRESH_PROCESS: \(mode) passed pid="))
	}
	try FileManager.default.removeItem(at: scratch)
}

func scaffoldProcessPath(_ pid: Int32) -> String? {
	var buffer = [UInt8](repeating: 0, count: 4096)
	let size = buffer.withUnsafeMutableBufferPointer { proc_pidpath(pid, $0.baseAddress, 4096) }
	guard
		size > 0,
		size <= 4096
	else { return nil }
	return String(decoding: buffer.prefix(Int(size)).prefix { $0 != 0 }, as: UTF8.self)
}

func scaffoldProcessStart(_ pid: Int32) -> UInt64? {
	var info = proc_bsdinfo()
	let size = Int32(MemoryLayout<proc_bsdinfo>.size)
	guard
		proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size
	else { return nil }
	return info.pbi_start_tvsec * 1000000 + info.pbi_start_tvusec
}

@MainActor func ownedScaffoldProcess(_ binary: URL) async throws -> (
	pid: Int32, start: UInt64
) {
	let deadline = ContinuousClock.now.advanced(by: .seconds(5))
	repeat {
		let output = try scaffoldCommand(
			URL(fileURLWithPath: "/bin/ps"), ["-axo", "pid="], timeout: 15, logOutput: false)
		let pids = output.split(separator: "\n").compactMap {
			Int32($0.trimmingCharacters(in: .whitespaces))
		}.filter {
			scaffoldProcessPath($0).map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path }
				== binary.resolvingSymlinksInPath().path
		}
		if let pid = pids.first {
			try #require(pids.count == 1)
			return (pid, try #require(scaffoldProcessStart(pid)))
		}
		try await Task.sleep(for: .milliseconds(50))
	} while ContinuousClock.now < deadline
	throw ScenarioFailure.message("No owned packaged executable")
}

@MainActor func stopScaffoldProcess(_ process: (pid: Int32, start: UInt64), binary: URL)
	async throws
{
	try #require(
		scaffoldProcessPath(process.pid).map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path }
			== binary.resolvingSymlinksInPath().path && scaffoldProcessStart(process.pid) == process.start
	)
	try #require(kill(process.pid, SIGTERM) == 0)
	let deadline = ContinuousClock.now.advanced(by: .seconds(10))
	// proc_pidinfo can disappear before the parent's monitor reaps the zombie.
	while kill(process.pid, 0) == 0 && ContinuousClock.now < deadline {
		try await Task.sleep(for: .milliseconds(50))
	}
	try #require(
		kill(process.pid, 0) != 0 && errno == ESRCH, "Owned development process not reaped; retain home"
	)
}

func stopScaffoldService(_ app: URL?, relative: String) throws {
	let binary = try #require(app).appendingPathComponent("Contents/XPCServices/" + relative)
	let expected = binary.resolvingSymlinksInPath().path
	let output = try scaffoldCommand(
		URL(fileURLWithPath: "/bin/ps"), ["-axo", "pid="], timeout: 15, logOutput: false)
	let pids = output.split(separator: "\n").compactMap {
		Int32($0.trimmingCharacters(in: .whitespaces))
	}.filter {
		scaffoldProcessPath($0).map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path }
			== expected
	}
	try #require(pids.count <= 1)
	for pid in pids {
		let start = try #require(scaffoldProcessStart(pid))
		try #require(
			scaffoldProcessPath(pid).map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path }
				== expected
				&& scaffoldProcessStart(pid) == start)
		try #require(kill(pid, SIGTERM) == 0)
		let gracefulDeadline = Date().addingTimeInterval(2)
		while kill(pid, 0) == 0 && Date() < gracefulDeadline { Thread.sleep(forTimeInterval: 0.05) }
		if kill(pid, 0) == 0 {
			// XPC launchd services can ignore TERM. All requests/owned development children are finished.
			// Revalidate both identities before forcing only this disposable service to exit.
			try #require(
				scaffoldProcessPath(pid).map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path }
					== expected
					&& scaffoldProcessStart(pid) == start)
			try #require(kill(pid, SIGKILL) == 0)
			print("CORE_DATA_SERVICE_ESCALATION: owned pid=\(pid) start=\(start) SIGKILL after TERM")
		}
		let deadline = Date().addingTimeInterval(10)
		while kill(pid, 0) == 0 && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
		try #require(kill(pid, 0) != 0 && errno == ESRCH, "Owned service not reaped; retain host/home")
		print("CORE_DATA_SERVICE_CLEANUP: pid=\(pid) start=\(start) path=\(expected) reaped")
	}
}
