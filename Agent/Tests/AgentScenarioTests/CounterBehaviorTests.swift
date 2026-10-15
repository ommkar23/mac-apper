// @frontmatter:start
// Compiles the independent counter test against direct/state presentation, wrong behavior, decoys, and retained Core Data source without model calls.
// @frontmatter:end
import Darwin
import Foundation
import Scenario
import Testing

@Test func createCounterOwnedServiceCleanupOffline() throws {
	let manager = FileManager.default
	let app = try ProjectTemporaryDirectory.appending(
		"mac-apper-counter-cleanup-\(UUID().uuidString).app")
	let relative = "Owned.xpc/Contents/MacOS/OwnedService"
	let binary = app.appendingPathComponent("Contents/XPCServices/" + relative)
	try manager.createDirectory(
		at: binary.deletingLastPathComponent(), withIntermediateDirectories: true)
	try manager.copyItem(at: URL(fileURLWithPath: "/bin/sleep"), to: binary)
	let owned = Process(), unrelated = Process()
	owned.executableURL = binary; owned.arguments = ["30"]
	unrelated.executableURL = URL(fileURLWithPath: "/bin/sleep"); unrelated.arguments = ["30"]
	try unrelated.run()
	defer {
		if unrelated.isRunning { unrelated.terminate() }
		unrelated.waitUntilExit()
		if owned.isRunning { owned.terminate(); owned.waitUntilExit() }
		try? manager.removeItem(at: app)
	}
	try owned.run()
	try stopScaffoldService(app, relative: relative)
	owned.waitUntilExit()
	#expect(kill(owned.processIdentifier, 0) != 0 && errno == ESRCH)
	#expect(unrelated.isRunning, "Exact-path teardown must not kill unrelated same-name processes")
	#expect(manager.fileExists(atPath: binary.path), "Reaping must precede signed-host removal")
	try manager.removeItem(at: app)
}

private func counterOfflineTestingCheckout(root: URL, override: String?) throws -> URL {
	let path = override ?? root.appendingPathComponent("Agent/.build/checkouts/swift-testing").path
	let components = path.split(separator: "/", omittingEmptySubsequences: false)
	guard
		path.hasPrefix("/"),
		components.dropFirst().allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }),
		!path.contains("\""), !path.contains("\\"),
		!path.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
	else { throw ScenarioFailure.message("Invalid AGENT_COUNTER_OFFLINE_TESTING_CHECKOUT path") }
	var current = ""
	for component in components.dropFirst() {
		current += "/" + component
		var info = stat()
		guard
			lstat(current, &info) == 0, info.st_mode & S_IFMT == S_IFDIR
		else {
			throw ScenarioFailure.message(
				"Missing or linked counter Testing checkout directory: \(current)")
		}
	}
	let checkout = URL(fileURLWithPath: path, isDirectory: true)
	var manifest = stat()
	guard
		lstat(checkout.appendingPathComponent("Package.swift").path, &manifest) == 0,
		manifest.st_mode & S_IFMT == S_IFREG,
		FileManager.default.isReadableFile(
			atPath: checkout.appendingPathComponent("Package.swift").path)
	else {
		throw ScenarioFailure.message(
			"Counter Testing checkout requires a readable regular Package.swift")
	}
	return checkout
}

@Test func counterOfflineTestingCheckoutValidation() throws {
	let root = try ProjectTemporaryDirectory.appending(
		"counter-checkout-validation-\(UUID().uuidString)")
	let manager = FileManager.default
	try manager.createDirectory(at: root, withIntermediateDirectories: true)
	defer { try? manager.removeItem(at: root) }
	let checkout = root.appendingPathComponent(
		"Agent/.build/checkouts/swift-testing", isDirectory: true)
	try manager.createDirectory(at: checkout, withIntermediateDirectories: true)
	for override in [
		nil, "", "relative", root.path + "/missing", root.path + "/../checkout",
		root.path + "/./checkout", root.path + "//checkout", root.path + "/quote\"",
		root.path + "/back\\slash",
		root.path + "/newline\n", checkout.path,
	] as [String?] {
		#expect(throws: (any Error).self) {
			try counterOfflineTestingCheckout(root: root, override: override)
		}
	}
	let manifest = checkout.appendingPathComponent("Package.swift")
	try "// validation fixture only; never evaluated".write(
		to: manifest, atomically: true, encoding: .utf8)
	#expect(try counterOfflineTestingCheckout(root: root, override: nil).path == checkout.path)
	#expect(
		try counterOfflineTestingCheckout(root: root, override: checkout.path).path == checkout.path)
	let link = root.appendingPathComponent("linked")
	try manager.createSymbolicLink(at: link, withDestinationURL: checkout)
	#expect(throws: (any Error).self) {
		try counterOfflineTestingCheckout(root: root, override: link.path)
	}
	#expect(throws: (any Error).self) {
		try counterOfflineTestingCheckout(
			root: root, override: link.appendingPathComponent("child").path)
	}
	try manager.removeItem(at: manifest)
	try manager.createSymbolicLink(at: manifest, withDestinationURL: URL(fileURLWithPath: #filePath))
	#expect(throws: (any Error).self) {
		try counterOfflineTestingCheckout(root: root, override: checkout.path)
	}
}

@Test @MainActor func counterBehaviorOfflineRegression() throws {
	let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
		.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
	let directory = try ProjectTemporaryDirectory.appending(
		"mac-apper-counter-offline-\(UUID().uuidString)")
	let project = directory.appendingPathComponent("project")
	let scratch = directory.appendingPathComponent("build")
	let manager = FileManager.default
	try manager.createDirectory(
		at: project.appendingPathComponent("Sources/AppModel"), withIntermediateDirectories: true)
	try manager.createDirectory(
		at: project.appendingPathComponent("Tests/AppModelTests"), withIntermediateDirectories: true)
	defer { try? manager.removeItem(at: directory) }
	let testing = try counterOfflineTestingCheckout(
		root: root,
		override: ProcessInfo.processInfo.environment["AGENT_COUNTER_OFFLINE_TESTING_CHECKOUT"])
	try """
	// swift-tools-version: 6.0
	import PackageDescription
	let package = Package(name: "CounterFixture", platforms: [.macOS(.v14)],
	    dependencies: [.package(path: "\(testing.path)")], targets: [
	        .target(name: "AppModel"),
	        .testTarget(name: "AppModelTests", dependencies: ["AppModel", .product(name: "Testing", package: "swift-testing")])])
	""".write(to: project.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
	let model = project.appendingPathComponent("Sources/AppModel/Model.swift")
	let check = project.appendingPathComponent("Tests/AppModelTests/ScenarioCounterTests.swift")
	let swift = try SwiftToolchain.executable("swift")
	func run(_ source: String) throws -> CounterCommandResult {
		try source.write(to: model, atomically: true, encoding: .utf8)
		try? manager.removeItem(at: check)
		let expression = try counterCountExpression(project: project, scratch: scratch)
		try counterBehaviorSource(expression).write(to: check, atomically: true, encoding: .utf8)
		return try counterCommand(
			swift,
			[
				"test", "--package-path", project.path, "--scratch-path", scratch.path, "-j", "2",
				"--filter", "scenarioCounterBehavior",
			])
	}
	let state = """
		import Foundation
		import CoreData
		import os
		public struct ApplicationState { public var count = 0 }
		@MainActor public final class ApplicationModel {
		    public var state = ApplicationState()
		    public let context: NSManagedObjectContext? = nil
		    public init() {}
		    public func increment() { state.count += 1 }
		    public func decrement() { state.count -= 1 }
		    public func reset() { state.count = 0 }
		    // public var count: Int { 999 } -- not an API
		    public let decoy = "public var count: Int { 999 }"
		}
		"""
	let stateResult = try run(state)
	#expect(stateResult.status == 0, "State-owned presentation must compile and pass")
	#expect(stateResult.output.contains("Test scenarioCounterBehavior() passed"))
	let direct = """
		@MainActor public final class ApplicationModel {
		    public var count = 0
		    public init() {}
		    public func increment() { count += 1 }
		    public func decrement() { count -= 1 }
		    public func reset() { count = 0 }
		    // public var state: ApplicationState -- not an API
		    public let decoy = "state.count"
		}
		"""
	let directResult = try run(direct)
	#expect(directResult.status == 0)
	#expect(directResult.output.contains("Test scenarioCounterBehavior() passed"))
	for bad in [
		direct.replacingOccurrences(of: "count += 1", with: "count += 2"),
		direct.replacingOccurrences(of: "count -= 1", with: "count = max(0, count - 1)"),
		state.replacingOccurrences(of: "state.count = 0", with: "state.count = 7"),
	] {
		let result = try run(bad)
		#expect(result.status != 0)
		#expect(
			result.output.contains("Test scenarioCounterBehavior() started"),
			"Wrong behavior must compile, execute, and fail assertions, not fail compilation")
		#expect(result.output.contains("Expectation failed"))
	}
	try
		(state.replacingOccurrences(
			of: "public init() {}", with: "public init() {}\n public var count: Int { state.count }"))
		.write(to: model, atomically: true, encoding: .utf8)
	try manager.removeItem(at: check)
	#expect(throws: (any Error).self) {
		try counterCountExpression(project: project, scratch: scratch)
	}
	try """
	@MainActor public final class ApplicationModel {
	    public init() {}
	    // public var count = 0
	    public let decoy = "state.count"
	}
	""".write(to: model, atomically: true, encoding: .utf8)
	#expect(throws: (any Error).self) {
		try counterCountExpression(project: project, scratch: scratch)
	}
	if let retained = ProcessInfo.processInfo.environment["COUNTER_OFFLINE_RETAINED_MODEL"] {
		// Explicit read-only evidence input, copied into this test-owned fixture. Never mutate originals.
		try manager.removeItem(at: model)
		let sources = URL(fileURLWithPath: retained)
		for name in [
			"ApplicationModel.swift", "ApplicationState.swift", "Persistence.swift",
			"AnimationIntent.swift",
		] {
			try manager.copyItem(
				at: sources.appendingPathComponent(name),
				to: project.appendingPathComponent("Sources/AppModel/" + name))
		}
		let expression = try counterCountExpression(project: project, scratch: scratch)
		#expect(expression == "model.state.count")
		try counterBehaviorSource(expression).write(to: check, atomically: true, encoding: .utf8)
		let result = try counterCommand(
			swift,
			[
				"test", "--package-path", project.path, "--scratch-path", scratch.path, "-j", "2",
				"--filter", "scenarioCounterBehavior",
			])
		#expect(result.status == 0)
		#expect(result.output.contains("Test scenarioCounterBehavior() passed"))
	}
}
