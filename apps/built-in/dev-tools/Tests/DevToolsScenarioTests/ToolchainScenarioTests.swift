// @frontmatter:start
// Verifies private-home Swift 6.4 Build/Run with a bounded release handshake and exact-owned cleanup.
// @frontmatter:end
import Darwin
import Foundation
import Scenario
import Testing

@Test @MainActor func devToolsToolchainBuildRunScenario() async throws {
	let lifecycle = DevToolsScenarioLifecycle()
	var bodyError: (any Error)?
	do {
		try lifecycle.setup()
		try await verifyToolchain(lifecycle)
		lifecycle.passed = true
	} catch { bodyError = error }
	// This runs after the body unwinds, even when that task was cancelled.
	do { try lifecycle.teardown() } catch {
		if let bodyError { throw DevToolsScenarioLifecycle.combined(bodyError, error) }
		throw error
	}
	if let bodyError { throw bodyError }
}

@MainActor private func verifyToolchain(_ lifecycle: DevToolsScenarioLifecycle) async throws {
	let projects = try #require(lifecycle.projects)
	let home = try #require(lifecycle.home)
	let fixture = try projects.create()
	let manifest = """
		// swift-tools-version: 6.0
		import PackageDescription
		let package = Package(name: "ToolchainFixture", platforms: [.macOS(.v14)], targets: [
		    .executableTarget(name: "ProductionApp")
		])
		"""
	try manifest.write(
		to: fixture.url.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
	let source = fixture.url.appendingPathComponent("Sources/ProductionApp/main.swift")
	try FileManager.default.createDirectory(
		at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
	try """
	#if compiler(<6.4)
	#error("Swift 6.4 is required")
	#endif
	import Darwin
	import Foundation
	let environment = ProcessInfo.processInfo.environment
	guard environment["HOME"] == \(String(reflecting: home.directory.path)),
	      environment["CFFIXED_USER_HOME"] == environment["HOME"],
	      environment["TMPDIR"] == \(String(reflecting: try ProjectTemporaryDirectory.root().path + "/"))
	else { exit(71) }
	for name in ["swift", "swiftc"] {
	    guard FileManager.default.isExecutableFile(atPath:
	        environment["HOME"]! + "/Library/Developer/Toolchains/swift-6.4.0-RELEASE.xctoolchain/usr/bin/" + name)
	    else { exit(72) }
	}
	let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
	guard root.path == \(String(reflecting: fixture.url.path)) else { exit(73) }
	try String(ProcessInfo.processInfo.processIdentifier).write(
	    to: root.appendingPathComponent("run-pid"), atomically: true, encoding: .utf8)
	let deadline = ProcessInfo.processInfo.systemUptime + 60
	while !FileManager.default.fileExists(atPath: root.appendingPathComponent("run-release").path) {
	    guard ProcessInfo.processInfo.systemUptime < deadline else { exit(74) }
	    Thread.sleep(forTimeInterval: 0.02)
	}
	""".write(to: source, atomically: true, encoding: .utf8)
	let original = try Data(contentsOf: source)
	let built = try lifecycle.perform {
		try $0.request("build", payload: ["projectRoot": fixture.url.path], projectID: fixture.id)
	}
	try #require(built["target"] as? String == "ProductionApp")
	lifecycle.childAttempted = true
	let launched = try lifecycle.perform {
		try $0.request("run", payload: ["projectRoot": fixture.url.path], projectID: fixture.id)
	}
	try #require(launched["target"] as? String == "ProductionApp")
	let relative = try #require(launched["relativePath"] as? String)
	let parts = relative.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
	try #require(parts.count == 4)
	try #require(parts[0] == ".mac-apper" && parts[1] == "DevBuild")
	let requestID = try #require(UUID(uuidString: parts[2]))
	try #require(parts[2] == requestID.uuidString.lowercased() && parts[3] == "ProductionApp.app")
	var current = fixture.url
	for part in parts + ["Contents", "MacOS"] {
		current.appendPathComponent(part)
		let values = try current.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
		try #require(values.isDirectory == true && values.isSymbolicLink != true)
	}
	let binary = current.appendingPathComponent("ProductionApp")
	try #require(FileManager.default.isExecutableFile(atPath: binary.path))
	let deadline = ContinuousClock.now.advanced(by: .seconds(10))
	let child = try ToolchainScenarioHandshake.acquire(
		binary: binary, root: fixture.url, lifecycle: lifecycle)
	print("DEVTOOLS_CHILD_CAPTURED pid=\(child.pid) start=\(child.start) path=\(child.path)")
	print("DEVTOOLS_CHILD_PRIVATE_HOME_COMPILER_CONFIRMED")
	while kill(child.pid, 0) == 0, ContinuousClock.now < deadline {
		try await Task.sleep(for: .milliseconds(50))
	}
	try child.requireReaped()
	try #require(try Data(contentsOf: source) == original)
	try #require(
		try String(contentsOf: fixture.url.appendingPathComponent("Package.swift"), encoding: .utf8)
			== manifest)
	try #require(
		!FileManager.default.fileExists(atPath: fixture.url.appendingPathComponent(".build").path))
}

// Keep polling, validation, exact capture, caching, corroboration and release in one
// synchronous MainActor window. Unrelated synchronous Preview work must not intervene.
@MainActor enum ToolchainScenarioHandshake {
	struct Operations {
		var now: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
		var ready: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }
		var wait: (TimeInterval) throws -> Void = Thread.sleep(forTimeInterval:)
		var capture: (URL) throws -> OwnedProcessIdentity = {
			try OwnedExecutableProcess.capture(executable: $0)
		}
		var release: (URL) throws -> Void = {
			try "release".write(to: $0, atomically: true, encoding: .utf8)
		}
	}

	static func acquire(
		binary: URL, root: URL, lifecycle: DevToolsScenarioLifecycle,
		using operations: Operations = Operations()
	) throws -> OwnedProcessIdentity {
		let marker = root.appendingPathComponent("run-pid")
		let deadline = operations.now() + 10
		while !operations.ready(marker), operations.now() < deadline {
			try operations.wait(0.02)
		}
		let values = try marker.resourceValues(forKeys: [
			.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey,
		])
		guard
			values.isRegularFile == true,
			values.isSymbolicLink != true,
			(values.fileSize ?? 65) <= 64,
			let pid = Int32(try String(contentsOf: marker, encoding: .utf8))
		else { throw ScenarioFailure.message("invalid development PID marker") }
		// Marker PID is only corroboration. Exact executable discovery confers authority.
		let child = try operations.capture(binary)
		lifecycle.child = child
		guard
			child.pid == pid
		else { throw ScenarioFailure.message("development PID marker mismatch") }
		try operations.release(root.appendingPathComponent("run-release"))
		return child
	}
}
